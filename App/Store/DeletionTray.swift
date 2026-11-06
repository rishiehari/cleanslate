import Foundation
import CleanSlateCore

/// One approved group waiting in the tray. Frozen at approval time; every item is
/// revalidated against the live library before anything is deleted.
struct TrayEntry: Codable, Identifiable, Equatable {
    var id: String { group.id }
    let group: PhotoReviewGroup
    let selectedIDs: Set<String>
    let manuallyReviewedIDs: Set<String>
    let approvedAt: Date

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

struct DeletionReceipt: Equatable {
    var requested = 0
    var verifiedRemoved = 0
    var uncertain = 0
    var logicalBytesRemoved: Int64 = 0
    /// Groups that could not be deleted (changed, vanished...), with a plain-words reason.
    var setAside: [String: String] = [:]
    var date = Date()
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
    @Published private(set) var reviewedGroupIDs: Set<String> = []
    @Published private(set) var toast: ToastState?
    @Published var receipt: DeletionReceipt?
    @Published private(set) var isDeleting = false

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

    var photoCount: Int {
        entries.reduce(0) { $0 + $1.selectedIDs.count } + standaloneEntries.reduce(0) { $0 + $1.items.count }
    }
    var verifiedBytes: Int64 {
        entries.reduce(Int64(0)) { $0 + $1.verifiedBytes } + standaloneEntries.reduce(Int64(0)) { $0 + $1.verifiedBytes }
    }
    var isEmpty: Bool { entries.isEmpty && standaloneEntries.isEmpty }
    func contains(_ groupID: String) -> Bool { entries.contains { $0.id == groupID } }

    // MARK: Approve / skip / undo

    func approve(group: PhotoReviewGroup, selected: Set<String>, manuallyReviewed: Set<String>) {
        guard !selected.isEmpty else { return }
        let entry = TrayEntry(group: group, selectedIDs: selected, manuallyReviewedIDs: manuallyReviewed, approvedAt: Date())
        let previous = entries.first { $0.id == group.id }
        let wasReviewed = reviewedGroupIDs.contains(group.id)
        entries.removeAll { $0.id == group.id }
        entries.append(entry)
        reviewedGroupIDs.insert(group.id)
        persist()
        show("Added \(selected.count) \(selected.count == 1 ? "photo" : "photos") to your tray") { [weak self] in
            guard let self else { return }
            self.entries.removeAll { $0.id == group.id }
            if let previous { self.entries.append(previous) }
            if !wasReviewed { self.reviewedGroupIDs.remove(group.id) }
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
        for item in items where !item.selected.isEmpty {
            entries.removeAll { $0.id == item.group.id }
            entries.append(TrayEntry(group: item.group, selectedIDs: item.selected, manuallyReviewedIDs: [], approvedAt: Date()))
            reviewedGroupIDs.insert(item.group.id)
        }
        persist()
        let n = items.reduce(0) { $0 + $1.selected.count }
        show("Added \(n) \(n == 1 ? "photo" : "photos") to your tray") { [weak self] in
            self?.entries = before.0; self?.reviewedGroupIDs = before.1; self?.persist()
        }
    }

    /// Adds keeper-less items. Items already in the tray are not added twice.
    func approveStandalone(items: [StandaloneItem]) {
        let existing = Set(standaloneEntries.flatMap { $0.items.map(\.id) })
        let fresh = items.filter { !existing.contains($0.id) }
        guard !fresh.isEmpty else { return }
        let entry = StandaloneTrayEntry(id: "standalone-\(UUID().uuidString)", items: fresh, approvedAt: Date())
        standaloneEntries.append(entry)
        persist()
        show("Added \(fresh.count) \(fresh.count == 1 ? "item" : "items") to your tray") { [weak self] in
            self?.standaloneEntries.removeAll { $0.id == entry.id }
            self?.persist()
        }
    }

    func remove(groupID: String) {
        entries.removeAll { $0.id == groupID }
        standaloneEntries.removeAll { $0.id == groupID }
        persist()
    }

    func clear() { entries = []; standaloneEntries = []; persist() }

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

    // MARK: Deleting (interim: one system prompt per group; Step 8 replaces this with a single batch)

    func deleteAll(using coordinator: PhotoDeletionCoordinator) async -> DeletionReceipt {
        guard !isDeleting else { return receipt ?? DeletionReceipt() }
        isDeleting = true
        defer { isDeleting = false }
        var result = DeletionReceipt()
        for entry in entries {
            result.requested += entry.selectedIDs.count
            do {
                let r = try await coordinator.commit(group: entry.group, selected: entry.selectedIDs,
                                                     manuallyReviewed: entry.manuallyReviewedIDs)
                result.verifiedRemoved += r.verifiedRemoved
                result.uncertain += r.uncertain
                result.logicalBytesRemoved += r.logicalBytesRemoved
                entries.removeAll { $0.id == entry.id }
            } catch {
                result.setAside[entry.id] = error.localizedDescription
                if (error as? CancellationError) != nil { break }
            }
            persist()
        }
        for entry in standaloneEntries {
            result.requested += entry.items.count
            do {
                let r = try await coordinator.commitStandalone(items: entry.items)
                result.verifiedRemoved += r.verifiedRemoved
                result.uncertain += r.uncertain
                result.logicalBytesRemoved += r.logicalBytesRemoved
                standaloneEntries.removeAll { $0.id == entry.id }
            } catch {
                result.setAside[entry.id] = error.localizedDescription
                if (error as? CancellationError) != nil { break }
            }
            persist()
        }
        receipt = result
        return result
    }

    // MARK: Persistence

    private struct Stored: Codable { var entries: [TrayEntry]; var reviewed: Set<String>; var standalone: [StandaloneTrayEntry]? }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        entries = stored.entries
        standaloneEntries = stored.standalone ?? []
        reviewedGroupIDs = stored.reviewed
    }

    private func persist() {
        guard let fileURL else { return }
        let data = try? JSONEncoder().encode(Stored(entries: entries, reviewed: reviewedGroupIDs, standalone: standaloneEntries))
        if let data { try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        // Photo identifiers are private and the tray is rebuildable: keep it out of device backups.
        var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
        var url = fileURL; try? url.setResourceValues(excluded)
    }
}
