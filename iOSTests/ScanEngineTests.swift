import XCTest
import CleanSlateCore
@testable import CleanSlate

@MainActor
final class ScanEngineTests: XCTestCase {
    private var library: FakePhotoLibrary!
    private var store: LibraryStore!

    override func setUp() async throws {
        library = FakePhotoLibrary()
        store = try LibraryStore(path: nil)
    }

    private func makeModel(governor: ResourceGovernor? = nil) -> CleaningViewModel {
        CleaningViewModel(library: library, tray: DeletionTray(fileURL: nil),
                          networkPolicy: NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { false }),
                          store: store, governor: governor)
    }

    private func seed(_ count: Int) {
        for i in 0..<count { library.add("p\(i)", content: "c\(i)") }
    }

    // MARK: Inventory

    func testNoCapOnLibrarySize() async {
        seed(2_300)
        let model = makeModel(); await model.runScan()
        XCTAssertEqual(model.statistics.photosEnumerated, 2_300, "the old 1,500/25,000 preview limits are gone")
        XCTAssertEqual(library.pageRequests, [0, 1_000, 2_000], "walked in pages of 1,000, never all at once")
    }

    func testInterruptedInventoryResumesInsteadOfRestarting() async {
        seed(2_500)
        let model = makeModel()
        library.onInventoryPage = { offset in if offset == 1_000 { model.stop() } }
        model.scan()
        try? await Task.sleep(for: .milliseconds(800))
        XCTAssertFalse(model.isScanning)
        let partial = await store.assetCount()
        XCTAssertTrue((1_000..<2_500).contains(partial), "a partial index was saved: \(partial)")
        library.onInventoryPage = nil
        let before = library.pageRequests.count
        await model.runScan()
        XCTAssertEqual(model.statistics.inventoryMode, .resumed)
        XCTAssertGreaterThan(library.pageRequests[before], 0, "resumed past page 0")
        let total = await store.assetCount()
        XCTAssertEqual(total, 2_500)
    }

    func testSecondScanIsIncrementalAndSkipsTheInventory() async {
        seed(30)
        let model = makeModel(); await model.runScan()
        XCTAssertEqual(model.statistics.inventoryMode, .full)
        let pagesAfterFirst = library.pageRequests.count
        library.add("new1", content: "n1")
        library.assets["p3"] = nil; library.recordChange(deleted: ["p3"])
        await model.runScan()
        XCTAssertEqual(model.statistics.inventoryMode, .incremental)
        XCTAssertEqual(library.pageRequests.count, pagesAfterFirst, "no pages were re-read")
        XCTAssertEqual(model.statistics.changesApplied, 2)
        let live = await store.snapshots(ids: ["new1", "p3"])
        XCTAssertNotNil(live["new1"]); XCTAssertNil(live["p3"])
    }

    func testExpiredTokenFallsBackToAFullInventoryAndNoticesDeletions() async {
        seed(20)
        let model = makeModel(); await model.runScan()
        library.assets["p5"] = nil                     // vanished with no change record
        library.changeTokensExpired = true
        await model.runScan()
        XCTAssertTrue(model.statistics.tokenExpired)
        XCTAssertEqual(model.statistics.inventoryMode, .full)
        let gone = await store.snapshots(ids: ["p5"])
        XCTAssertNil(gone["p5"], "assets missing after a full re-inventory are marked deleted")
        let total = await store.assetCount()
        XCTAssertEqual(total, 19)
    }

    func testUnsupportedChangeTrackingStillWorksViaFullInventory() async {
        seed(10)
        library.changeTrackingAvailable = false
        let model = makeModel(); await model.runScan(); await model.runScan()
        XCTAssertEqual(model.statistics.inventoryMode, .full)
        XCTAssertEqual(model.statistics.photosEnumerated, 10)
    }

    // MARK: Fingerprints

    func testFingerprintsAreCachedAcrossScans() async {
        seed(25)
        let model = makeModel(); await model.runScan()
        XCTAssertEqual(model.statistics.thumbnailsAnalyzed, 25)
        let callsAfterFirst = library.thumbnailCalls
        await model.runScan()
        XCTAssertEqual(model.statistics.thumbnailsAnalyzed, 0, "nothing to recompute")
        XCTAssertEqual(library.thumbnailCalls, callsAfterFirst, "no thumbnails were requested again")
    }

    func testEditedPhotoIsFingerprintedAgainAndOthersAreNot() async {
        seed(10)
        let model = makeModel(); await model.runScan()
        library.update("p2", revision: "edited")
        await model.runScan()
        XCTAssertEqual(model.statistics.thumbnailsAnalyzed, 1)
    }

    func testAssetsWithoutALocalThumbnailAreCountedNotRetriedForever() async {
        seed(6)
        library.unavailableThumbnailIDs = ["p0", "p1"]
        let model = makeModel(); await model.runScan()
        XCTAssertEqual(model.statistics.cloudOnlyOrUnavailable, 2)
        XCTAssertEqual(model.statistics.thumbnailsAnalyzed, 4)
        XCTAssertFalse(model.isScanning)
        // They become local later: the next scan tries them again.
        library.unavailableThumbnailIDs = []
        await model.runScan()
        XCTAssertEqual(model.statistics.thumbnailsAnalyzed, 2)
    }

    // MARK: Resource governor

    private func governor(thermal: @escaping @Sendable () -> ProcessInfo.ThermalState,
                          memory: @escaping @Sendable () -> Int = { 1_000_000_000 },
                          lowPower: @escaping @Sendable () -> Bool = { false },
                          maxPause: Int = 600) -> ResourceGovernor {
        ResourceGovernor(inputs: .init(thermalState: thermal, availableMemoryBytes: memory, lowPowerMode: lowPower, sleep: { _ in }),
                         cores: 8, maximumPauseSeconds: maxPause)
    }

    func testConcurrencyFollowsThermalMemoryAndPowerState() async {
        let nominal = await governor(thermal: { .nominal }).checkpoint()
        XCTAssertEqual(nominal, .proceed(concurrency: 4))
        let fair = await governor(thermal: { .fair }).checkpoint()
        XCTAssertEqual(fair, .proceed(concurrency: 2))
        let lowMemory = await governor(thermal: { .nominal }, memory: { 50_000_000 }).checkpoint()
        XCTAssertEqual(lowMemory, .proceed(concurrency: 1))
        let lowPower = await governor(thermal: { .nominal }, lowPower: { true }).checkpoint()
        XCTAssertEqual(lowPower, .proceed(concurrency: 2))
    }

    func testCriticalHeatStopsAndSeriousHeatPausesThenResumes() async {
        let critical = await governor(thermal: { .critical }).checkpoint()
        guard case .stop = critical else { return XCTFail("critical must stop") }

        let calls = Counter()
        let cooling = governor(thermal: { calls.next() < 3 ? .serious : .nominal })
        let result = await cooling.checkpoint()
        XCTAssertEqual(result, .proceed(concurrency: 4), "waited, then continued once it cooled")
        XCTAssertNil(cooling.pauseReason)

        let stuck = governor(thermal: { .serious }, maxPause: 6)
        let gaveUp = await stuck.checkpoint()
        guard case .stop = gaveUp else { return XCTFail("a phone that stays hot ends the scan") }
    }

    func testScanStoppedByHeatKeepsItsProgressAndTheNextScanContinues() async {
        seed(450)
        let state = Counter()
        // Cool for the first batches, then critical.
        let hot = governor(thermal: { state.next() > 3 ? .critical : .nominal })
        let model = makeModel(governor: hot)
        await model.runScan()
        XCTAssertEqual(model.phase, .cancelled)
        XCTAssertTrue(model.statusMessage?.contains("very warm") == true, model.statusMessage ?? "")
        let saved = await store.featureCount()
        XCTAssertGreaterThan(saved, 0, "fingerprints done before the stop are kept")
        XCTAssertLessThan(saved, 450)
        let cool = makeModel(governor: governor(thermal: { .nominal }))
        await cool.runScan()
        XCTAssertEqual(cool.statistics.thumbnailsAnalyzed, 450 - saved, "only the remaining photos are processed")
        XCTAssertEqual(cool.statistics.inventoryMode, .incremental)
    }
}

/// Thread-safe counter used to script changing conditions.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var value = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}
