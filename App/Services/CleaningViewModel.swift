import Foundation
import Photos
import Combine
import CleanSlateCore

@MainActor
final class CleaningViewModel: ObservableObject, ScanReporting {
    @Published private(set) var authorization: PHAuthorizationStatus
    @Published private(set) var phase: ScanPhase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var groups: [PhotoReviewGroup] = [] { didSet { recomputeStandalone() } }
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
            self?.invalidateAfterLibraryChange()
        }
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

    /// A library change makes shown results untrustworthy. (Step 6 narrows this to only the affected groups.)
    private func invalidateAfterLibraryChange() {
        if isScanning { scanTask?.cancel() }
        let hadResults = !groups.isEmpty || !standaloneItems.isEmpty
        groups = []
        standaloneItems = []
        if hadResults { statusMessage = "The Photos library changed. Previous results were cleared. Scan again." }
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
