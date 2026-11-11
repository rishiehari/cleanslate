import XCTest
import CleanSlateCore
@testable import CleanSlate

/// The `scan.inProgress` marker: set/read/clear round-trip through `LibraryStore.meta`, and cleared on every
/// ScanEngine outcome path (clean end, cancel, governor stop) so only a killed process leaves it behind.
@MainActor
final class ScanInProgressMarkerTests: XCTestCase {
    private var library: FakePhotoLibrary!
    private var store: LibraryStore!
    private var dir: URL!

    override func setUp() async throws {
        library = FakePhotoLibrary()
        store = try LibraryStore(path: nil)
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("marker-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeModel(governor: ResourceGovernor? = nil) -> CleaningViewModel {
        CleaningViewModel(library: library, tray: DeletionTray(fileURL: nil),
                          networkPolicy: NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { false }),
                          store: store, governor: governor, diagnostics: DiagnosticsLog(directory: dir))
    }

    private func seed(_ count: Int) {
        for i in 0..<count { library.add("p\(i)", content: "c\(i)") }
    }

    func testSetReadClearRoundTrip() async {
        let missing = await ScanInProgressMarker.read(in: store)
        XCTAssertNil(missing)
        await ScanInProgressMarker.set(.vision, in: store)
        let value = await ScanInProgressMarker.read(in: store)
        XCTAssertEqual(value?.phase, .vision)
        XCTAssertNotNil(value?.at)
        await ScanInProgressMarker.clear(in: store)
        let afterClear = await ScanInProgressMarker.read(in: store)
        XCTAssertNil(afterClear)
        let metaRow = await store.meta(ScanInProgressMarker.metaKey)
        XCTAssertNil(metaRow, "the meta row itself is deleted")
    }

    func testEngineClearsMarkerOnCleanEndAndRecordsScanEvents() async {
        seed(5)
        let model = makeModel()
        await model.runScan()
        XCTAssertEqual(model.phase, .finished)
        let marker = await ScanInProgressMarker.read(in: store)
        XCTAssertNil(marker)
        XCTAssertEqual(model.scanCounters.snapshot.phase, .finished, "watchdog attribution after a finished scan")
        // The engine recorded into the injected log: the whole F02.3 wiring is live.
        // (Heartbeat emission itself is covered by ScanHeartbeatTests; a 5-asset scan can finish
        //  before the first 2 s beat, so no heartbeat assertion belongs here.)
        let events = model.diagnostics.recent(limit: 100).map(\.event)
        XCTAssertTrue(events.contains { if case .scanStarted = $0 { true } else { false } })
        XCTAssertTrue(events.contains { if case .scanEnded(let outcome, _, _) = $0 { outcome == .finished } else { false } })
    }

    func testMarkerIsSetDuringScanAndClearedOnCancel() async {
        seed(2_500)
        let model = makeModel()
        let markerDuringScan: ScanInProgressMarker.Value? = await withCheckedContinuation { continuation in
            var resumed = false
            library.onInventoryPage = { [self] offset in
                guard offset == 0, !resumed else { return }
                resumed = true
                Task { [self] in
                    let value = await ScanInProgressMarker.read(in: self.store)
                    model.stop()
                    continuation.resume(returning: value)
                }
            }
            model.scan()
        }
        XCTAssertEqual(markerDuringScan?.phase, .inventory, "the marker was written at the first phase boundary")
        var spins = 0
        while model.isScanning, spins < 200 { try? await Task.sleep(for: .milliseconds(50)); spins += 1 }
        XCTAssertFalse(model.isScanning, "the cancelled scan unwound")
        let marker = await ScanInProgressMarker.read(in: store)
        XCTAssertNil(marker, "the cancel path cleared the marker")
        XCTAssertEqual(model.scanCounters.snapshot.phase, .idle, "watchdog attribution after a paused scan")
    }

    func testEngineClearsMarkerWhenGovernorStopsTheScan() async {
        seed(20)
        let governor = ResourceGovernor(inputs: .init(thermalState: { .critical },
                                                      availableMemoryBytes: { .max }, lowPowerMode: { false },
                                                      memoryPressure: { .normal }, sleep: { _ in }), maximumPauseSeconds: 1)
        let model = makeModel(governor: governor)
        await model.runScan()
        XCTAssertEqual(model.phase, .cancelled)
        XCTAssertNotNil(model.statusMessage)
        let marker = await ScanInProgressMarker.read(in: store)
        XCTAssertNil(marker, "the stop path cleared the marker")
    }
}
