import Foundation
import Photos
import CleanSlateCore

/// One approved group waiting in the tray. Frozen at approval time; every item is
/// revalidated against the live library before anything is deleted.
struct TrayEntry: Codable, Identifiable, Equatable {
    var id: String { group.id }
    let group: PhotoReviewGroup
    let selectedIDs: Set<String>
    let manuallyReviewedIDs: Set<String>
    let approvedAt: Date
    /// The photos the user chose to KEEP (several are allowed). nil = just the group's suggested keeper.
    var keeperIDs: Set<String>? = nil

    var effectiveKeeperIDs: Set<String> { keeperIDs ?? [group.keeper.id] }
    /// The photos this approval actually depends on (not the undecided bystanders in a big group).
    var involvedIDs: Set<String> { selectedIDs.union(effectiveKeeperIDs) }

    var verifiedBytes: Int64 { selectedIDs.reduce(Int64(0)) { $0 + (group.verifiedCandidateBytes[$1] ?? 0) } }
    static func == (a: TrayEntry, b: TrayEntry) -> Bool {
        a.id == b.id && a.selectedIDs == b.selectedIDs && a.manuallyReviewedIDs == b.manuallyReviewedIDs
    }
}

/// Keeper-less items (screenshots, recordings, large videos) the user approved, as one tray row.
struct StandaloneTrayEntry: Codable, Identifiable, Equatable {
    let id: String
    let items: [StandaloneItem]
    let approvedAt: Date
    var verifiedBytes: Int64 { items.reduce(Int64(0)) { $0 + ($1.verifiedBytes ?? 0) } }
}

struct DeletionReceipt: Equatable, Codable, Identifiable {
    var id = UUID()
    var requested = 0
    var verifiedRemoved = 0
    var uncertain = 0
    var logicalBytesRemoved: Int64 = 0
    /// Groups that could not be deleted (changed, vanished...), with a plain-words reason.
    var setAside: [String: String] = [:]
    var date = Date()
    /// Free space on the iPhone just before and just after. Deleted photos stay in Recently Deleted for 30 days,
    /// so the real gain only shows after that is emptied; these two numbers are measurements, not promises.
    var freeBytesBefore: Int64?
    var freeBytesAfter: Int64?
}

enum FreeSpace {
    /// Space the system says is available for important use, or nil if it can't be read.
    static func available() -> Int64? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        return (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }
}

struct ToastState: Equatable, Identifiable {
    let id = UUID()
    let message: String
    let undoable: Bool
}

/// The Deletion tray (U1): approved groups wait here. Approving never deletes.
@MainActor
final class DeletionTray: ObservableObject {
    @Published private(set) var entries: [TrayEntry] = []
    @Published private(set) var standaloneEntries: [StandaloneTrayEntry] = []
    /// Entries that changed since approval, with the plain-words reason. They are never deleted until the user looks again.
    @Published private(set) var needsAttention: [String: String] = [:]
    /// Entries a protection rule invalidated. Persisted, and only ever cleared by the user (send back to review, remove,
    /// clear, or approving the same group again), so removing a rule or relaunching can never make them deletable again.
    @Published private(set) var protectionInvalidatedIDs: Set<String> = []
    /// Set by the owner of the rules (CleaningViewModel). Used to check a review draft against the rules when it is approved.
    weak var protectionGate: ProtectionGate?
    @Published private(set) var reviewedGroupIDs: Set<String> = []
    @Published private(set) var toast: ToastState?
    @Published var receipt: DeletionReceipt?
    @Published private(set) var isDeleting = false
    /// Plain-words explanation when a delete did not go through (blocked groups, cancelled check, a failure).
    @Published var batchNotice: String?
    /// "Double-checking N of M" while the originals are rechecked before the Apple prompt.
    @Published private(set) var checkProgress: (done: Int, total: Int)?

    private let fileURL: URL?
    private var undoAction: (() -> Void)?
    private var toastTask: Task<Void, Never>?

    /// `fileURL == nil` keeps everything in memory (tests).
    init(fileURL: URL?) {
        self.fileURL = fileURL
        load()
    }

    static func defaultURL(name: String = "tray.json") -> URL? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true) else { return nil }
        return dir.appendingPathComponent(name)
    }

    /// Only entries that are still fine count toward what will be deleted.
    var readyEntries: [TrayEntry] { entries.filter { isReady($0.id) } }
    var readyStandaloneEntries: [StandaloneTrayEntry] { standaloneEntries.filter { isReady($0.id) } }
    private func isReady(_ id: String) -> Bool { needsAttention[id] == nil && !protectionInvalidatedIDs.contains(id) }
    var photoCount: Int {
        readyEntries.reduce(0) { $0 + $1.selectedIDs.count } + readyStandaloneEntries.reduce(0) { $0 + $1.items.count }
    }
    var verifiedBytes: Int64 {
        readyEntries.reduce(Int64(0)) { $0 + $1.verifiedBytes } + readyStandaloneEntries.reduce(Int64(0)) { $0 + $1.verifiedBytes }
    }
    var isEmpty: Bool { entries.isEmpty && standaloneEntries.isEmpty }
    var hasReadyItems: Bool { !readyEntries.isEmpty || !readyStandaloneEntries.isEmpty }

    /// Replaces the recomputed reasons. Entries a protection rule invalidated always keep their reason.
    func setNeedsAttention(_ reasons: [String: String]) {
        var merged = reasons
        let live = Set(entries.map(\.id) + standaloneEntries.map(\.id))
        for id in protectionInvalidatedIDs where live.contains(id) { merged[id] = TrayChecker.protectedByRuleReason }
        needsAttention = merged
    }

    /// A protection rule now covers these entries. They need the user's fresh review before they can be deleted again.
    func markProtectionInvalidated(_ ids: Set<String>) {
        let live = Set(entries.map(\.id) + standaloneEntries.map(\.id))
        let relevant = ids.intersection(live)
        guard !relevant.isEmpty else { return }
        protectionInvalidatedIDs.formUnion(relevant)
        for id in relevant { needsAttention[id] = TrayChecker.protectedByRuleReason }
        persist()
    }

    private func clearProtectionInvalidation(_ ids: Set<String>) {
        protectionInvalidatedIDs.subtract(ids)
    }

    /// Takes an entry out of the tray and returns the group to the review inbox.
    func sendBackToReview(_ id: String) {
        entries.removeAll { $0.id == id }
        standaloneEntries.removeAll { $0.id == id }
        reviewedGroupIDs.remove(id)
        needsAttention[id] = nil
        clearProtectionInvalidation([id])
        persist()
    }
    func contains(_ groupID: String) -> Bool { entries.contains { $0.id == groupID } }

    // MARK: Approve / skip / undo

    func approve(group: PhotoReviewGroup, selected: Set<String>, manuallyReviewed: Set<String>, keepers: Set<String>? = nil) {
        guard !selected.isEmpty else { return }
        let entry = TrayEntry(group: group, selectedIDs: selected, manuallyReviewedIDs: manuallyReviewed, approvedAt: Date(),
                              keeperIDs: keepers)
        let previous = entries.first { $0.id == group.id }
        let wasReviewed = reviewedGroupIDs.contains(group.id)
        let wasInvalidated = protectionInvalidatedIDs.contains(group.id)
        entries.removeAll { $0.id == group.id }
        entries.append(entry)
        reviewedGroupIDs.insert(group.id)
        if wasInvalidated { needsAttention[group.id] = nil }
        clearProtectionInvalidation([group.id])
        persist()
        show("Added \(selected.count) \(selected.count == 1 ? "photo" : "photos") to your tray") { [weak self] in
            guard let self else { return }
            self.entries.removeAll { $0.id == group.id }
            if let previous { self.entries.append(previous) }
            if !wasReviewed { self.reviewedGroupIDs.remove(group.id) }
            // Undoing a re-approval must not resurrect an entry a rule had invalidated.
            if wasInvalidated, previous != nil { self.markProtectionInvalidated([group.id]) }
            self.persist()
        }
    }

    func skip(groupID: String) {
        let wasReviewed = reviewedGroupIDs.contains(groupID)
        reviewedGroupIDs.insert(groupID)
        persist()
        show("Skipped") { [weak self] in
            guard let self else { return }
            if !wasReviewed { self.reviewedGroupIDs.remove(groupID) }
            self.persist()
        }
    }

    func approveAll(_ items: [(group: PhotoReviewGroup, selected: Set<String>)]) {
        let before = (entries, reviewedGroupIDs)
        let invalidatedBefore = protectionInvalidatedIDs
        for item in items where !item.selected.isEmpty {
            entries.removeAll { $0.id == item.group.id }
            entries.append(TrayEntry(group: item.group, selectedIDs: item.selected, manuallyReviewedIDs: [], approvedAt: Date()))
            reviewedGroupIDs.insert(item.group.id)
            if protectionInvalidatedIDs.contains(item.group.id) { needsAttention[item.group.id] = nil }
            clearProtectionInvalidation([item.group.id])
        }
        persist()
        let n = items.reduce(0) { $0 + $1.selected.count }
        show("Added \(n) \(n == 1 ? "photo" : "photos") to your tray") { [weak self] in
            self?.entries = before.0; self?.reviewedGroupIDs = before.1
            self?.markProtectionInvalidated(invalidatedBefore)
            self?.persist()
        }
    }

    /// Adds keeper-less items. Items already in the tray are not added twice.
    func approveStandalone(items: [StandaloneItem]) {
        let existing = Set(standaloneEntries.flatMap { $0.items.map(\.id) })
        let fresh = items.filter { !existing.contains($0.id) }
        guard !fresh.isEmpty else { return }
        // One Apple prompt covers at most `maximumBatchTargets` photos, so a big selection becomes several entries.
        let size = SafetyPolicy.maximumBatchTargets
        let added = stride(from: 0, to: fresh.count, by: size).map { start in
            StandaloneTrayEntry(id: "standalone-\(UUID().uuidString)", items: Array(fresh[start..<min(start + size, fresh.count)]), approvedAt: Date())
        }
        standaloneEntries.append(contentsOf: added)
        persist()
        let addedIDs = Set(added.map(\.id))
        show("Added \(fresh.count) \(fresh.count == 1 ? "item" : "items") to your tray") { [weak self] in
            self?.standaloneEntries.removeAll { addedIDs.contains($0.id) }
            self?.persist()
        }
    }

    func remove(groupID: String) {
        entries.removeAll { $0.id == groupID }
        standaloneEntries.removeAll { $0.id == groupID }
        if protectionInvalidatedIDs.contains(groupID) { needsAttention[groupID] = nil }
        clearProtectionInvalidation([groupID])
        persist()
    }

    func clear() {
        entries = []; standaloneEntries = []
        needsAttention = needsAttention.filter { !protectionInvalidatedIDs.contains($0.key) }
        protectionInvalidatedIDs = []
        persist()
    }

    func undo() {
        undoAction?()
        undoAction = nil
        dismissToast()
    }

    func dismissToast() { toastTask?.cancel(); toast = nil }

    private func show(_ message: String, undo: @escaping () -> Void) {
        undoAction = undo
        let state = ToastState(message: message, undoable: true)
        toast = state
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, self?.toast?.id == state.id else { return }
            self?.toast = nil
            self?.undoAction = nil
        }
    }

    // MARK: Deleting (the whole tray is ONE request and ONE Apple prompt)

    /// Sends every ready entry to the coordinator as a single batch. Returns the receipt, or nil when nothing was
    /// deleted (the batch was blocked, the user cancelled the system prompt, or the check was cancelled).
    func deleteAll(using coordinator: PhotoDeletionCoordinator) async -> DeletionReceipt? {
        guard !isDeleting else { return nil }
        isDeleting = true
        batchNotice = nil
        checkProgress = nil
        defer { isDeleting = false; checkProgress = nil }
        var total = DeletionReceipt()
        total.freeBytesBefore = FreeSpace.available()
        var anyCompleted = false
        // Whole-tray consistency BEFORE chunking, over EVERY entry (ready or set aside): the batch policy only
        // sees one chunk at a time, and a set-aside entry's kept photo is still a photo the user chose to keep,
        // so a ready entry must never delete it. Entries already set aside keep their existing reason.
        let conflicts = Self.wholeTrayConflicts(groups: entries, standalone: standaloneEntries,
                                                limit: SafetyPolicy.maximumBatchTargets)
        let newlySetAside = conflicts.filter { needsAttention[$0.key] == nil }
        if !newlySetAside.isEmpty {
            var attention = needsAttention
            for (id, reason) in newlySetAside { attention[id] = reason }
            needsAttention = attention
            let n = newlySetAside.count
            let rest = readyEntries.isEmpty && readyStandaloneEntries.isEmpty
                ? "Nothing was deleted." : "Nothing was deleted. Tap Delete again to remove the rest."
            batchNotice = "\(n) \(n == 1 ? "item needs" : "items need") another look and \(n == 1 ? "was" : "were") set aside. " + rest
            return nil
        }
        let chunks = Self.chunks(groups: readyEntries, standalone: readyStandaloneEntries, limit: SafetyPolicy.maximumBatchTargets)
        guard !chunks.isEmpty else {                       // nothing ready to delete
            if !entries.isEmpty || !standaloneEntries.isEmpty {
                batchNotice = "Nothing is ready to delete. Items that need another look stay in your tray."
            }
            return nil
        }
        do {
            for chunk in chunks {
                let outcome = try await coordinator.commitBatch(groups: chunk.groups, standalone: chunk.standalone) { [weak self] done, count in
                    self?.checkProgress = (done, count)
                }
                switch outcome {
                case .blocked(let reasons):
                    var attention = needsAttention
                    for (id, reason) in reasons { attention[id] = reason }
                    needsAttention = attention
                    // A rule blocked these: that stays true even if the rule is later removed.
                    markProtectionInvalidated(Set(reasons.filter { $0.value == TrayChecker.protectedByRuleReason }.keys))
                    let n = reasons.count
                    batchNotice = "\(n) \(n == 1 ? "group" : "groups") changed since you approved \(n == 1 ? "it" : "them") and \(n == 1 ? "was" : "were") set aside. "
                        + (anyCompleted ? "The earlier part was deleted; the rest is still in your tray." : "Nothing was deleted. Tap Delete again to remove the rest.")
                    return anyCompleted ? finish(total) : nil
                case .completed(let done):
                    anyCompleted = true
                    entries.removeAll { done.removedEntryIDs.contains($0.id) }
                    standaloneEntries.removeAll { done.removedEntryIDs.contains($0.id) }
                    persist()
                    total.requested += done.requested; total.verifiedRemoved += done.verifiedRemoved
                    total.uncertain += done.uncertain; total.logicalBytesRemoved += done.logicalBytesRemoved
                }
            }
            return finish(total)
        } catch is CancellationError {
            batchNotice = anyCompleted ? "Stopped. The earlier part was deleted; the rest is still in your tray." : "Stopped. Nothing was deleted."
            return anyCompleted ? finish(total) : nil
        } catch let error as PHPhotosError where error.code == .userCancelled {
            return anyCompleted ? finish(total) : nil          // the user said no in Apple's prompt
        } catch {
            batchNotice = error.localizedDescription
            return anyCompleted ? finish(total) : nil
        }
    }

    private func finish(_ total: DeletionReceipt) -> DeletionReceipt {
        var done = total
        done.freeBytesAfter = FreeSpace.available()
        done.date = Date()
        receipt = done
        return done
    }

    nonisolated static let overlapAcrossTrayReason = "This photo is also kept or chosen in another group, so these need another look"
    nonisolated static let tooLargeReason = "This group has too many photos for one deletion. Review it in smaller parts"

    /// Entries that must be set aside before any chunk is committed (entry id → user-facing reason).
    /// The decision is `CleanSlateCore.TrayConsistency` (Core, tested); this only adapts tray entries to it.
    nonisolated static func wholeTrayConflicts(groups: [TrayEntry], standalone: [StandaloneTrayEntry],
                                               limit: Int) -> [String: String] {
        let entries = groups.map { TrayConsistency.Entry(id: $0.id, targets: $0.selectedIDs, keepers: $0.effectiveKeeperIDs) }
            + standalone.map { TrayConsistency.Entry(id: $0.id, targets: Set($0.items.map(\.id)), keepers: []) }
        return TrayConsistency.problems(entries, limit: limit).mapValues { problem in
            switch problem {
            case .overlapsAnotherEntry: overlapAcrossTrayReason
            case .tooLarge: tooLargeReason
            }
        }
    }

    /// Apple's single prompt is limited to `limit` photos here (a safety bound), so a bigger tray is split into batches.
    nonisolated static func chunks(groups: [TrayEntry], standalone: [StandaloneTrayEntry],
                                   limit: Int) -> [(groups: [TrayEntry], standalone: [StandaloneTrayEntry])] {
        var result: [(groups: [TrayEntry], standalone: [StandaloneTrayEntry])] = []
        var current: (groups: [TrayEntry], standalone: [StandaloneTrayEntry]) = ([], [])
        var count = 0
        func add(size: Int, _ place: () -> Void) {
            if count + size > limit, count > 0 { result.append(current); current = ([], []); count = 0 }
            place(); count += size
        }
        for entry in groups { add(size: entry.selectedIDs.count) { current.groups.append(entry) } }
        for entry in standalone { add(size: entry.items.count) { current.standalone.append(entry) } }
        if count > 0 { result.append(current) }
        return result
    }

    /// How many Apple prompts the current tray will need.
    var promptCount: Int { max(1, Self.chunks(groups: readyEntries, standalone: readyStandaloneEntries, limit: SafetyPolicy.maximumBatchTargets).count) }

    // MARK: Persistence

    private struct Stored: Codable {
        var entries: [TrayEntry]; var reviewed: Set<String>; var standalone: [StandaloneTrayEntry]?
        /// Added by N05. Optional so a tray file written by an older build still decodes.
        var protectionInvalidated: Set<String>?
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        entries = stored.entries
        standaloneEntries = stored.standalone ?? []
        reviewedGroupIDs = stored.reviewed
        let live = Set(entries.map(\.id) + standaloneEntries.map(\.id))
        protectionInvalidatedIDs = (stored.protectionInvalidated ?? []).intersection(live)
        for id in protectionInvalidatedIDs { needsAttention[id] = TrayChecker.protectedByRuleReason }
    }

    private func persist() {
        guard let fileURL else { return }
        let live = Set(entries.map(\.id) + standaloneEntries.map(\.id))
        if !protectionInvalidatedIDs.isSubset(of: live) { protectionInvalidatedIDs.formIntersection(live) }
        let data = try? JSONEncoder().encode(Stored(entries: entries, reviewed: reviewedGroupIDs, standalone: standaloneEntries,
                                                    protectionInvalidated: protectionInvalidatedIDs))
        if let data { try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        // Photo identifiers are private and the tray is rebuildable: keep it out of device backups.
        var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
        var url = fileURL; try? url.setResourceValues(excluded)
    }
}
