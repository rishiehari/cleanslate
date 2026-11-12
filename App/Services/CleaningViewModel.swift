import Foundation
import Photos
import Combine
import CleanSlateCore

/// What the progress UI reads (F03.9): published at most twice per second from the 0.5 s tick.
struct ScanProgressSnapshot: Equatable {
    var phase: ScanPhase = .idle
    var done = 0
    var total = 0
    var foundGroups = 0
    var foundBytesVerified: Int64 = 0
    var pauseReason: String?
    var isStalled = false
    var startedAt: Date?
}

/// Engine -> view-model write buffer. The engine's reporting calls are frequent; publishing is
/// coalesced by the 0.5 s tick. Lock-protected like ScanCounters.
private final class ScanProgressBuffer: @unchecked Sendable {
    struct State {
        var phase: ScanPhase = .idle
        var progress: Double = 0
        var statistics = ScanStatistics()
        var pendingGroups: [PhotoReviewGroup] = []
        var standalone: [StandaloneItem]?
        var albumMembers: Set<String> = []
    }
    private let lock = NSLock()
    private var state = State()
    func withLock<T>(_ body: (inout State) -> T) -> T { lock.lock(); defer { lock.unlock() }; return body(&state) }
}

@MainActor
final class CleaningViewModel: ObservableObject, ScanReporting {
    @Published private(set) var authorization: PHAuthorizationStatus
    @Published private(set) var phase: ScanPhase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var groups: [PhotoReviewGroup] = []
    /// Groups being rechecked after a library change. Their Approve button is disabled meanwhile.
    @Published private(set) var recheckingGroupIDs: Set<String> = []
    private var membership = GroupMembershipIndex()
    /// Members of exact groups, maintained incrementally; standalone items hide these.
    private var exactMemberIDs: Set<String> = []
    /// DEBUG/test observability: how often the standalone cache was rebuilt.
    private(set) var standaloneRecomputeCount = 0
    private let progressBuffer = ScanProgressBuffer()
    @Published private(set) var progressSnapshot = ScanProgressSnapshot()
    private var isProcessingChanges = false
    private var changesDirty = false
    private var changesArrivedDuringScan = false
    @Published private(set) var standaloneItems: [StandaloneItem] = []
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
    /// True while the F02 heartbeat sees a stall episode (F05 renders the stall message).
    @Published private(set) var isScanStalled = false

    // MARK: Scan Scope Support
    @Published private(set) var activityOverview: PhotoActivitySummary?
    @Published private(set) var activityOverviewLoading = false
    @Published private(set) var activityOverviewError: String?
    @Published private(set) var currentScanPeriod: PhotoActivityPeriod?

    var currentScanTitle: String {
        if let period = currentScanPeriod {
            return "Week of \(period.start.formatted(date: .abbreviated, time: .omitted))"
        }
        return currentScanScope.title
    }

    func loadActivityOverview() async {
        guard authorization == .authorized || authorization == .limited else {
            activityOverview = nil
            return
        }
        guard activityOverview == nil, !activityOverviewLoading else { return }
        activityOverviewLoading = true
        activityOverviewError = nil
        defer { activityOverviewLoading = false }
        do {
            let summary = try await library.activitySummary()
            try Task.checkCancellation()
            activityOverview = summary
        } catch {
            if !Task.isCancelled {
                activityOverviewError = "Photos didn't respond in time. You can still start a small scan or try the overview again."
            }
        }
    }

    @Published private(set) var currentScanScope: ScanScope = .recentMonth

    let library: PhotoLibraryClient
    private let coordinator: PhotoDeletionCoordinator
    let tray: DeletionTray
    let networkPolicy: NetworkPolicy
    let store: LibraryStore
    let governor: ResourceGovernor
    let visual: VisualAnalyzing
    /// Local diagnostics log; the engine records into it, the heartbeat and the watchdog read/write it.
    let diagnostics: DiagnosticsLog
    /// Lock-protected scan counters shared with the engine, the heartbeat and the main-thread watchdog.
    let scanCounters: ScanCounters
    private lazy var engine: ScanEngine = {
        let engine = ScanEngine(library: library, store: store, networkPolicy: networkPolicy, governor: governor,
                                visual: visual, counters: scanCounters)
        engine.reporter = self
        engine.diagnostics = diagnostics
        return engine
    }()
    private var scanTask: Task<Void, Never>?
    private var scanStartedAt: ContinuousClock.Instant?
    /// Test observability for the engine's cache contents.
    var debugEngineCacheCounts: (prints: Int, quality: Int) { engine.debugCacheCounts }

    private var scanStartedAtDate: Date?
    private var continuedProcessingRequested = false
    private var changeSubscription: ChangeSubscription?
    /// Describes faces and text for the "different people / different text" warnings (replaced by a fake in UI tests).
    lazy var analyzer: PhotoAnalyzer = VisionPhotoAnalyzer(library: library)

    init(library: PhotoLibraryClient = PhotoKitLibraryClient.shared,
         tray: DeletionTray? = nil,
         networkPolicy: NetworkPolicy? = nil,
         store: LibraryStore? = nil,
         governor: ResourceGovernor? = nil,
         visual: VisualAnalyzing = VisionVisualAnalyzer(),
         diagnostics: DiagnosticsLog? = nil,
         scanCounters: ScanCounters = ScanCounters()) {
        self.visual = visual
        self.library = library
        self.networkPolicy = networkPolicy ?? NetworkPolicy.shared
        self.tray = tray ?? DeletionTray(fileURL: DeletionTray.defaultURL())
        self.store = store ?? ((try? LibraryStore(path: LibraryStore.defaultPath())) ?? (try! LibraryStore(path: nil)))
        self.governor = governor ?? ResourceGovernor()
        self.diagnostics = diagnostics ?? DiagnosticsLog.shared
        self.scanCounters = scanCounters
        self.governor.diagnostics = self.diagnostics
        self.coordinator = PhotoDeletionCoordinator(library: library, networkPolicy: self.networkPolicy)
        self.authorization = library.authorization
        // @Published notifies before the value changes, so use the emitted value, not tray.standaloneEntries.
        trayObserver = self.tray.$standaloneEntries.sink { [weak self] entries in self?.recomputeStandalone(trayEntries: entries) }
        governorObserver = self.governor.$pauseReason.sink { [weak self] reason in self?.pauseReason = reason }
        changeSubscription = library.observeChanges { [weak self] in
            self?.libraryDidChange()
        }
        self.governor.dropCachesRequested = { [weak self] in self?.engine.dropCaches() }
        revalidateTray(touched: nil)          // anything approved earlier may have changed while the app was closed
    }

    func setScanScope(_ scope: ScanScope) {
        guard !isScanning, scanTask == nil, ScanScope.userScopes.contains(scope) else { return }
        currentScanScope = scope
        currentScanPeriod = nil
    }

    func refreshPermissions() {
        let newStatus = library.authorization
        if newStatus != authorization {
            scanTask?.cancel()
            resetResults()
            activityOverview = nil
            currentScanPeriod = nil
            currentScanScope = .recentMonth
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
        resetResults()
        statusMessage = "The Photos library changed. Previous results were cleared. Scan again."
    }

    /// Clears groups, standalone items and their indexes (internal for tests; everything routes here).
    func resetResults() {
        groups = []
        standaloneItems = []
        membership = GroupMembershipIndex()
        exactMemberIDs = []
        recomputeStandalone()
    }

    /// The single entry point for group mutations (F03.9): updates the array in ONE write (the
    /// re-render bound counts objectWillChange), the membership index incrementally, and (only when
    /// exact membership moved) the standalone cache. Replaces the old didSet.
    func didChangeGroups(added: [PhotoReviewGroup] = [], removed: [String] = []) {
        guard !added.isEmpty || !removed.isEmpty else { return }
        var exactTouched = !removed.isEmpty
        let removedIDs = Set(removed)
        var appended: [PhotoReviewGroup] = []
        var replacements: [(index: Int, group: PhotoReviewGroup)] = []
        for group in added {
            if let index = groups.firstIndex(where: { $0.id == group.id }) {
                if groups[index].kind == .exact || group.kind == .exact { exactTouched = true }
                replacements.append((index, group))
                membership.upsert(groupID: group.id, members: Set(group.all.map(\.id)))
            } else {
                if group.kind == .exact { exactTouched = true }
                appended.append(group)
                membership.upsert(groupID: group.id, members: Set(group.all.map(\.id)))
            }
        }
        if !removedIDs.isEmpty {
            groups.removeAll { removedIDs.contains($0.id) }
        }
        if !appended.isEmpty {
            groups.append(contentsOf: appended)          // ONE published write per flush
        }
        for replacement in replacements {
            groups[replacement.index] = replacement.group
        }
        guard exactTouched else { return }
        let updated = Set(groups.filter { $0.kind == .exact }.flatMap { $0.all.map(\.id) })
        if updated != exactMemberIDs {
            exactMemberIDs = updated
            recomputeStandalone()
        }
    }

    /// The single entry point for standalone-item replacements.
    private func didChangeStandalone(_ items: [StandaloneItem]) {
        guard items != standaloneItems else { return }
        standaloneItems = items
        recomputeStandalone()
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
            case .updated(let updated): didChangeGroups(added: [updated])
            case .dissolved: didChangeGroups(removed: [id])
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
        didChangeStandalone(refreshed)
    }

    /// Re-judges approved entries. `touched == nil` checks everything (at launch).
    func revalidateTray(touched: Set<String>?) {
        let checker = TrayChecker(library: library)
        var reasons = tray.needsAttention
        for entry in tray.entries where touched.map({ !$0.isDisjoint(with: entry.involvedIDs) }) ?? true {
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
        standaloneRecomputeCount += 1
        let inTray = Set((trayEntries ?? tray.standaloneEntries).flatMap { $0.items.map(\.id) })
        // Members of an exact-copy group are handled there (one is always kept). Offering them here
        // would let someone delete every copy of the same photo or video.
        let hidden = inTray.union(exactMemberIDs).union(albumMembers)
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
        recomputeStandalone()      // byte counts feed the category lists
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
        resetResults()
        didChangeGroups(added: seeded)
        didChangeStandalone(standalone)
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

    /// Past deletions, newest first.
    func loadHistory() async -> [DeletionReceipt] {
        await store.receiptJSONs().compactMap { $0.data(using: .utf8).flatMap { try? JSONDecoder().decode(DeletionReceipt.self, from: $0) } }
    }

    // MARK: Scanning

    /// Runs one scan to completion. `scan()` wraps this in a cancellable task; tests await it directly.
    /// Explicit internal default preserves full-library regression coverage. Product entry is scan(),
    /// which always captures the selected bounded scope before scheduling the task.
    func runScan(with scope: ScanScope = .all, inventoryRequest: ScanInventoryRequest? = nil) async {
        guard !isScanning, authorization == .authorized || authorization == .limited else { return }
        isScanning = true
        statistics = ScanStatistics(); statusMessage = nil; progress = 0
        resetResults()
        progressBuffer.withLock { $0 = ScanProgressBuffer.State() }
        networkPolicy.resetSessionBudget()          // the iCloud download limit is per scan
        // The heartbeat makes a stall visible in the on-device log (every 2 s) without Xcode attached.
        let heartbeat = ScanHeartbeat(log: diagnostics, counters: scanCounters)
        heartbeat.onStall = { [weak self] _ in
            Task { @MainActor in self?.isScanStalled = true }
        }
        heartbeat.onStallEnd = { [weak self] in
            Task { @MainActor in self?.isScanStalled = false }
        }
        heartbeat.start()
        defer { heartbeat.stop() }
        if isScanStalled { isScanStalled = false }
        scanStartedAt = .now
        scanStartedAtDate = Date()
        continuedProcessingRequested = false
        let tick = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { break }
                self?.publishProgressSnapshot()
            }
        }
        defer { tick.cancel() }
        let outcome = await engine.run(scope: scope, inventoryRequest: inventoryRequest)
        publishProgressSnapshot()                    // final synchronous flush before finishScan reads statistics
        finishScan(outcome)
        progressBuffer.withLock { s in s.phase = self.phase; s.progress = self.progress }   // finishScan may advance them
        publishProgressSnapshot()                    // snapshot mirrors the finished phase for the UI
        isScanning = false
        if changesArrivedDuringScan {              // the library moved while we were scanning: recheck what that touched
            changesArrivedDuringScan = false
            await processLibraryChange()
        }
    }

    func scan(scope: ScanScope? = nil) {
        guard !isScanning, scanTask == nil else { return }
        let chosen = scope ?? currentScanScope
        guard ScanScope.userScopes.contains(chosen) || (chosen == .activityRange && currentScanPeriod != nil) else { return }
        if chosen != .activityRange { currentScanPeriod = nil }
        beginScan(scope: chosen, request: chosen == .activityRange ? selectedPeriodRequest : nil)
    }

    func scan(period: PhotoActivityPeriod) {
        guard !isScanning, scanTask == nil else { return }
        currentScanPeriod = period
        beginScan(scope: .activityRange, request: selectedPeriodRequest)
    }

    private var selectedPeriodRequest: ScanInventoryRequest? {
        currentScanPeriod.map { ScanInventoryRequest(maximumItems: 2_000, earliestDate: $0.start, latestDate: $0.end.addingTimeInterval(-0.001)) }
    }

    private func beginScan(scope: ScanScope, request: ScanInventoryRequest?) {
        guard !isScanning, scanTask == nil else { return }
        currentScanScope = scope
        scanTask = Task { [weak self] in
            await self?.runScan(with: scope, inventoryRequest: request)
            self?.scanTask = nil
        }
    }

    /// Background continuation uses the same bounded selection as the foreground button.
    func runSelectedScan() async {
        await withTaskCancellationHandler {
            if scanTask == nil { scan() }
            await scanTask?.value
        } onCancel: {
            Task { @MainActor [weak self] in self?.stop() }
        }
    }

    #if DEBUG
    /// Keeps historical full-library cancellation/fault tests explicit; never exposed in product UI.
    func scanAllForTesting() { beginScan(scope: .all, request: nil) }
    #endif

    func stop() { scanTask?.cancel() }

    /// Ends the current scan stage early and moves on (F03.8). Skipping never marks anything as
    /// matched. A skip requested while no scan is running is ignored (never consumed).
    func skipCurrentStage() { guard isScanning else { return }; engine.skipCurrentStage() }

    func clearIndex() {
        guard !isScanning else { return }
        let store = self.store
        Task { try? await store.reset() }
        resetResults()
        statistics = ScanStatistics()
        statusMessage = "Saved scan data was cleared. Your photos weren't touched."
    }

    /// Deletes everything in the tray with ONE Apple prompt (after the user confirmed in the summary sheet).
    /// Everything is still fully revalidated by the coordinator. Returns true if photos were actually removed.
    @discardableResult
    func deleteTray() async -> Bool {
        let candidateAssets = Set(tray.readyEntries.flatMap(\.selectedIDs) + tray.readyStandaloneEntries.flatMap { $0.items.map(\.id) })
        let readyGroupIDs = Set(tray.readyEntries.map(\.id))
        guard let receipt = await tray.deleteAll(using: coordinator) else { return false }
        let leftInTray = Set(tray.entries.map(\.id))
        didChangeGroups(removed: readyGroupIDs.subtracting(leftInTray).sorted())
        didChangeStandalone(standaloneItems.filter { library.snapshot(id: $0.id, inspectAlbums: false) != nil })
        // Keep the index honest about what is gone (only assets that really disappeared).
        let removed = candidateAssets.filter { library.snapshot(id: $0, inspectAlbums: false) == nil }
        if !removed.isEmpty { try? await store.markDeleted(Array(removed)) }
        if receipt.verifiedRemoved > 0 { HapticsService.shared.fire(.batchDeleted) }
        if let data = try? JSONEncoder().encode(receipt), let json = String(data: data, encoding: .utf8) {
            try? await store.addReceipt(id: receipt.id.uuidString, createdAt: receipt.date, json: json)
        }
        return true
    }

    private func finishScan(_ outcome: ScanEngine.Outcome) {
        groups.sort { $0.kind == $1.kind ? $0.estimatedVerifiedBytes > $1.estimatedVerifiedBytes : $0.kind == .exact }
        let seconds = scanStartedAt.map { Int($0.duration(to: .now).components.seconds) } ?? 0
        switch outcome {
        case .cancelled:
            phase = .cancelled
            statusMessage = "Scan paused. Available results are ready to review. Scan again to recheck the selected range."
            diagnostics.record(.scanEnded(outcome: .paused, seconds: seconds, groupsFound: groups.count))
        case .stopped(let reason):
            phase = .cancelled
            statusMessage = reason
            diagnostics.record(.scanEnded(outcome: .stopped, seconds: seconds, groupsFound: groups.count))
        case .finished:
            phase = .finished; progress = 1
            diagnostics.record(.scanEnded(outcome: .finished, seconds: seconds, groupsFound: groups.count))
            var message = "Looked through \(statistics.photosEnumerated.formatted()) photos."
            if statistics.exactAssetsUnverifiable > 0 { message += " Some originals live only in iCloud, so matches there may be missed." }
            if statistics.visionUnavailable { message += " Similar-photo comparison isn't available on this device, so only identical copies were checked." }
            else if statistics.visionFailures > 0 { message += " Similar-photo comparison failed for \(statistics.visionFailures) pair(s)." }
            if statistics.exactSkippedByLimit > 0 { message += " \(statistics.exactSkippedByLimit.formatted()) candidates were not checked in this scan." }
            statusMessage = message
        }
    }

    // MARK: ScanReporting (writes the buffer; the 0.5 s tick publishes)

    func scanDidEnter(_ phase: ScanPhase) { progressBuffer.withLock { $0.phase = phase } }
    func scanProgress(_ value: Double) { progressBuffer.withLock { s in s.progress = max(s.progress, min(1, value)) } }
    func scanUpdate(_ change: (inout ScanStatistics) -> Void) { progressBuffer.withLock { change(&$0.statistics) } }
    func scanFound(groups found: [PhotoReviewGroup]) {
        guard !found.isEmpty else { return }
        progressBuffer.withLock { $0.pendingGroups.append(contentsOf: found) }   // flushed on the tick (U12)
    }
    func scanFoundStandalone(_ items: [StandaloneItem], albumMembers: Set<String>) {
        progressBuffer.withLock { s in
            s.standalone = items
            s.albumMembers = albumMembers
        }
    }

    /// Applies the buffer at <= 2 Hz: publishes phase/progress/statistics, flushes pending groups
    /// (incremental membership + exact-member bookkeeping), and refreshes the snapshot struct.
    private func publishProgressSnapshot() {
        let buffered = progressBuffer.withLock { state -> (phase: ScanPhase, progress: Double, statistics: ScanStatistics, groups: [PhotoReviewGroup], standalone: [StandaloneItem]?, albums: Set<String>) in
            let out = (state.phase, state.progress, state.statistics, state.pendingGroups, state.standalone, state.albumMembers)
            state.pendingGroups = []
            state.standalone = nil
            return out
        }
        if phase != buffered.phase { phase = buffered.phase }
        if progress != buffered.progress { progress = buffered.progress }
        statistics = buffered.statistics
        // A scan of more than 500 items may continue after the user leaves the app (F03.10).
        if statistics.photosEnumerated > 500, !continuedProcessingRequested {
            continuedProcessingRequested = true
            BackgroundScanning.requestContinuedProcessing()
        }
        didChangeGroups(added: buffered.groups)
        if let standalone = buffered.standalone {
            albumMembers = buffered.albums
            didChangeStandalone(standalone)
        }
        let counters = scanCounters.snapshot
        let snapshot = ScanProgressSnapshot(phase: phase, done: counters.done, total: counters.total,
                                            foundGroups: groups.count, foundBytesVerified: potentialVerifiedBytes,
                                            pauseReason: pauseReason, isStalled: isScanStalled,
                                            startedAt: scanStartedAtDate)
        if snapshot != progressSnapshot { progressSnapshot = snapshot }
    }
}
