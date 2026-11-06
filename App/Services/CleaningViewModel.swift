import Foundation
import Photos
import Combine
import CleanSlateCore

@MainActor
final class CleaningViewModel: ObservableObject, ScanReporting {
    @Published private(set) var authorization: PHAuthorizationStatus
    @Published private(set) var phase: ScanPhase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var groups: [PhotoReviewGroup] = [] { didSet { recomputeStandalone(); rebuildMembership() } }
    /// Groups being rechecked after a library change. Their Approve button is disabled meanwhile.
    @Published private(set) var recheckingGroupIDs: Set<String> = []
    private var membership = GroupMembershipIndex()
    private var isProcessingChanges = false
    private var changesDirty = false
    private var changesArrivedDuringScan = false
    @Published private(set) var standaloneItems: [StandaloneItem] = [] { didSet { recomputeStandalone() } }
    /// Cached per category: the lists are read many times per screen update.
    private(set) var standaloneCache: [ScanCategory: [StandaloneItem]] = [:]
    private var albumMembers: Set<String> = []
    private var trayObserver: AnyCancellable?
    private var governorObserver: AnyCancellable?
    @Published private(set) var statistics = ScanStatistics()
    @Published var statusMessage: String?
    @Published private(set) var isScanning = false
    /// Why the scan is paused right now (e.g. "Paused — your iPhone is warm"), if it is.
    @Published private(set) var pauseReason: String?

    let library: PhotoLibraryClient
    private let coordinator: PhotoDeletionCoordinator
    let tray: DeletionTray
    let networkPolicy: NetworkPolicy
    let store: LibraryStore
    let governor: ResourceGovernor
    private lazy var engine: ScanEngine = {
        let engine = ScanEngine(library: library, store: store, networkPolicy: networkPolicy, governor: governor)
        engine.reporter = self
        return engine
    }()
    private var scanTask: Task<Void, Never>?
    private var changeSubscription: ChangeSubscription?

    init(library: PhotoLibraryClient = PhotoKitLibraryClient.shared,
         tray: DeletionTray? = nil,
         networkPolicy: NetworkPolicy? = nil,
         store: LibraryStore? = nil,
         governor: ResourceGovernor? = nil) {
        self.library = library
        self.networkPolicy = networkPolicy ?? NetworkPolicy.shared
        self.tray = tray ?? DeletionTray(fileURL: DeletionTray.defaultURL())
        self.store = store ?? ((try? LibraryStore(path: LibraryStore.defaultPath())) ?? (try! LibraryStore(path: nil)))
        self.governor = governor ?? ResourceGovernor()
        self.coordinator = PhotoDeletionCoordinator(library: library, networkPolicy: self.networkPolicy)
        self.authorization = library.authorization
        // @Published notifies before the value changes, so use the emitted value, not tray.standaloneEntries.
        trayObserver = self.tray.$standaloneEntries.sink { [weak self] entries in self?.recomputeStandalone(trayEntries: entries) }
        governorObserver = self.governor.$pauseReason.sink { [weak self] reason in self?.pauseReason = reason }
        changeSubscription = library.observeChanges { [weak self] in
            self?.libraryDidChange()
        }
        revalidateTray(touched: nil)          // anything approved earlier may have changed while the app was closed
    }

    func refreshPermissions() {
        let newStatus = library.authorization
        if newStatus != authorization {
            scanTask?.cancel()
            groups = []
            standaloneItems = []
            statusMessage = "Photos access changed. Please scan again."
        }
        authorization = newStatus
    }

    // MARK: Live invalidation (only what changed is rechecked)

    /// Called by PhotoKit (via the observer). Changes are processed one pass at a time; a change that
    /// arrives during a pass triggers one more pass.
    private func libraryDidChange() {
        if isScanning { changesArrivedDuringScan = true; return }
        changesDirty = true
        guard !isProcessingChanges else { return }
        isProcessingChanges = true
        Task { [weak self] in
            while let self, self.changesDirty {
                self.changesDirty = false
                await self.processLibraryChange()
            }
            self?.isProcessingChanges = false
        }
    }

    /// Catches the index up with the library and rechecks ONLY the groups, lists and tray entries that contain a changed asset.
    func processLibraryChange() async {
        let hasResults = !groups.isEmpty || !standaloneItems.isEmpty || !tray.isEmpty
        guard let token = await store.meta(LibrarySync.Meta.token), await store.meta(LibrarySync.Meta.complete) != nil else {
            if hasResults { clearResultsAfterUnknownChange() }
            return
        }
        switch library.changes(since: token) {
        case .changes(let set):
            await LibrarySync.apply(set, library: library, store: store)
            let touched = set.changedIDs.union(set.deletedIDs)
            guard !touched.isEmpty else { return }
            await recheckGroups(affectedBy: touched)
            refreshStandalone(touched: touched)
            revalidateTray(touched: touched)
        case .tokenExpired, .unavailable:
            if hasResults { clearResultsAfterUnknownChange() }
        }
    }

    private func clearResultsAfterUnknownChange() {
        groups = []
        standaloneItems = []
        statusMessage = "The Photos library changed. Previous results were cleared. Scan again."
    }

    private func rebuildMembership() {
        membership = GroupMembershipIndex(groups: Dictionary(uniqueKeysWithValues: groups.map { ($0.id, Set($0.all.map(\.id))) }))
    }

    private func recheckGroups(affectedBy touched: Set<String>) async {
        let affected = membership.groupsAffected(by: touched)
        guard !affected.isEmpty else { return }
        recheckingGroupIDs.formUnion(affected)
        let rechecker = GroupRechecker(library: library, networkPolicy: networkPolicy, albums: albumMembers)
        for id in affected.sorted() {
            defer { recheckingGroupIDs.remove(id) }
            guard let group = groups.first(where: { $0.id == id }) else { continue }
            switch await rechecker.recheck(group) {
            case .unchanged: break
            case .updated(let updated): if let index = groups.firstIndex(where: { $0.id == id }) { groups[index] = updated }
            case .dissolved: groups.removeAll { $0.id == id }
            }
        }
    }

    private func refreshStandalone(touched: Set<String>) {
        guard standaloneItems.contains(where: { touched.contains($0.id) }) else { return }
        var refreshed: [StandaloneItem] = []
        for item in standaloneItems {
            guard touched.contains(item.id) else { refreshed.append(item); continue }
            guard let fresh = library.snapshot(id: item.id, inspectAlbums: false) else { continue }      // gone
            let sameFile = fresh.record.revision == item.snapshot.record.revision
            refreshed.append(StandaloneItem(snapshot: fresh, verifiedBytes: sameFile ? item.verifiedBytes : nil))
        }
        standaloneItems = refreshed
    }

    /// Re-judges approved entries. `touched == nil` checks everything (at launch).
    func revalidateTray(touched: Set<String>?) {
        let checker = TrayChecker(library: library)
        var reasons = tray.needsAttention
        for entry in tray.entries where touched.map({ !$0.isDisjoint(with: entry.group.all.map(\.id)) }) ?? true {
            reasons[entry.id] = checker.reasonNeedingAnotherLook(entry)
        }
        for entry in tray.standaloneEntries where touched.map({ !$0.isDisjoint(with: entry.items.map(\.id)) }) ?? true {
            reasons[entry.id] = checker.reasonNeedingAnotherLook(entry)
        }
        let live = Set(tray.entries.map(\.id) + tray.standaloneEntries.map(\.id))
        tray.setNeedsAttention(reasons.filter { live.contains($0.key) })
    }

    func groups(in category: ScanCategory) -> [PhotoReviewGroup] {
        guard let kind = category.groupKind else { return [] }
        return groups.filter { group in
            guard group.kind == kind else { return false }
            switch category {
            case .exact: return !group.keeper.isVideo
            case .videos: return group.keeper.isVideo
            default: return true
            }
        }
    }

    func standalone(in category: ScanCategory) -> [StandaloneItem] { standaloneCache[category] ?? [] }

    private func recomputeStandalone(trayEntries: [StandaloneTrayEntry]? = nil) {
        let inTray = Set((trayEntries ?? tray.standaloneEntries).flatMap { $0.items.map(\.id) })
        // Members of an exact-copy group are handled there (one is always kept). Offering them here
        // would let someone delete every copy of the same photo or video.
        let inExactGroup = Set(groups.filter { $0.kind == .exact }.flatMap { $0.all.map(\.id) })
        let hidden = inTray.union(inExactGroup).union(albumMembers)
        var cache: [ScanCategory: [StandaloneItem]] = [:]
        for category in ScanCategory.allCases {
            guard let kind = category.standaloneKind else { continue }
            cache[category] = StandaloneRules.items(for: kind, from: standaloneItems).filter { !hidden.contains($0.id) }
        }
        standaloneCache = cache
    }

    /// Measures a screenshot's size when the user selects it (cheap for one file; avoids reading thousands up front).
    func measureSize(of item: StandaloneItem) async {
        guard item.verifiedBytes == nil, let bytes = await library.verifiedSize(id: item.id) else { return }
        if let index = standaloneItems.firstIndex(where: { $0.id == item.id }) { standaloneItems[index].verifiedBytes = bytes }
    }

    func verifiedBytes(in category: ScanCategory) -> Int64 {
        if category.standaloneKind != nil {
            return standalone(in: category).reduce(Int64(0)) { $0 + ($1.verifiedBytes ?? 0) }
        }
        return groups(in: category).reduce(Int64(0)) { $0 + $1.estimatedVerifiedBytes }
    }

    func count(in category: ScanCategory) -> Int {
        category.standaloneKind != nil ? standalone(in: category).count : groups(in: category).count
    }

    /// Why this item can't be selected right now (e.g. it sits in one of the user's albums), or nil.
    func selectionBlockReason(for item: StandaloneItem) -> String? {
        guard let fresh = library.snapshot(id: item.id, inspectAlbums: true) else { return "No longer in your library" }
        guard fresh.record.revision == item.snapshot.record.revision else { return "Changed since the scan. Scan again" }
        if let flag = fresh.record.flags.sorted(by: { $0.rawValue < $1.rawValue }).first { return flag.userFacingReason }
        return nil
    }

    #if DEBUG
    /// UI tests and screenshots only: show prepared groups without running a scan.
    func seedGroupsForUITesting(_ seeded: [PhotoReviewGroup], standalone: [StandaloneItem] = []) {
        groups = seeded
        standaloneItems = standalone
        phase = .finished
        progress = 1
    }
    #endif

    var potentialVerifiedBytes: Int64 {
        groups.reduce(Int64(0)) { $0 + $1.estimatedVerifiedBytes }
    }

    func requestPermission() {
        Task { authorization = await library.requestAccess() }
    }

    // MARK: Scanning

    /// Runs one scan to completion. `scan()` wraps this in a cancellable task; tests await it directly.
    func runScan() async {
        guard !isScanning, authorization == .authorized || authorization == .limited else { return }
        isScanning = true
        statistics = ScanStatistics(); statusMessage = nil; groups = []; standaloneItems = []; progress = 0
        networkPolicy.resetSessionBudget()          // the iCloud download limit is per scan
        let outcome = await engine.run()
        finishScan(outcome)
        isScanning = false
        if changesArrivedDuringScan {              // the library moved while we were scanning: recheck what that touched
            changesArrivedDuringScan = false
            await processLibraryChange()
        }
    }

    func scan() {
        guard !isScanning else { return }
        scanTask = Task { [weak self] in
            await self?.runScan()
            self?.scanTask = nil
        }
    }

    func stop() { scanTask?.cancel() }

    func clearIndex() {
        guard !isScanning else { return }
        let store = self.store
        Task { try? await store.reset() }
        groups = []
        standaloneItems = []
        statistics = ScanStatistics()
        statusMessage = "Saved scan data was cleared. Your photos weren't touched."
    }

    /// Deletes everything in the tray (after the user confirmed in the summary sheet).
    /// Each group is still fully revalidated by the coordinator, and Apple shows its own prompt.
    func deleteTray() async {
        let idsBefore = Set(tray.entries.map(\.id))
        let candidateAssets = Set(tray.entries.flatMap(\.selectedIDs) + tray.standaloneEntries.flatMap { $0.items.map(\.id) })
        let receipt = await tray.deleteAll(using: coordinator)
        let deleted = idsBefore.subtracting(tray.entries.map(\.id))
        groups.removeAll { deleted.contains($0.id) }
        standaloneItems.removeAll { library.snapshot(id: $0.id, inspectAlbums: false) == nil }
        // Keep the index honest about what is gone (only assets that really disappeared).
        let removed = candidateAssets.filter { library.snapshot(id: $0, inspectAlbums: false) == nil }
        if !removed.isEmpty { try? await store.markDeleted(Array(removed)) }
        if receipt.verifiedRemoved > 0 { HapticsService.shared.fire(.batchDeleted) }
    }

    private func finishScan(_ outcome: ScanEngine.Outcome) {
        groups.sort { $0.kind == $1.kind ? $0.estimatedVerifiedBytes > $1.estimatedVerifiedBytes : $0.kind == .exact }
        switch outcome {
        case .cancelled:
            phase = .cancelled
            statusMessage = "Scan paused. Your progress is saved, and the next scan picks up from here."
        case .stopped(let reason):
            phase = .cancelled
            statusMessage = reason
        case .finished:
            phase = .finished; progress = 1
            var message = "Looked through \(statistics.photosEnumerated.formatted()) photos."
            if statistics.exactAssetsUnverifiable > 0 { message += " Some originals live only in iCloud, so matches there may be missed." }
            if statistics.visionUnavailable { message += " Similar-photo comparison isn't available on this device, so only identical copies were checked." }
            else if statistics.visionFailures > 0 { message += " Similar-photo comparison failed for \(statistics.visionFailures) pair(s)." }
            if statistics.exactSkippedByLimit > 0 { message += " \(statistics.exactSkippedByLimit.formatted()) candidates were left for the next scan." }
            statusMessage = message
        }
    }

    // MARK: ScanReporting

    func scanDidEnter(_ phase: ScanPhase) { self.phase = phase }
    func scanProgress(_ value: Double) { progress = max(progress, min(1, value)) }
    func scanUpdate(_ change: (inout ScanStatistics) -> Void) { change(&statistics) }
    func scanFound(groups found: [PhotoReviewGroup]) {
        guard !found.isEmpty else { return }
        let existing = Set(groups.map(\.id))
        groups += found.filter { !existing.contains($0.id) }      // appear while the scan runs (U12)
    }
    func scanFoundStandalone(_ items: [StandaloneItem], albumMembers: Set<String>) {
        self.albumMembers = albumMembers
        standaloneItems = items
    }
}
