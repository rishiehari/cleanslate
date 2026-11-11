import XCTest
import CleanSlateCore
@testable import CleanSlate

/// F03.11 acceptance: the main-thread watchdog records no >250 ms block ATTRIBUTED TO SCAN PHASES
/// during a 10,000-photo fake scan with thumbnails ON. (Re-render bound: ViewModelCoalescingTests.)
@MainActor
final class F03AcceptanceTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("f03acc-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func testWatchdogRecordsNoScanAttributedBlocksDuring10000PhotoScan() async throws {
        let log = DiagnosticsLog(directory: dir)
        let counters = ScanCounters()
        let watchdog = MainThreadWatchdog(log: log, probes: .init(phase: { counters.snapshot.phase }))
        let library = FakePhotoLibrary.burstHeavy(count: 10_000, burstShare: 0.3, burstLength: 6, seed: 5)
        let model = try ScanTestRig.model(library: library, diagnostics: log, scanCounters: counters)
        watchdog.start()
        await model.runScan()
        watchdog.stop()
        XCTAssertEqual(model.statistics.photosEnumerated, 10_000)
        let scanPhases: Set<DiagPhase> = [.inventory, .thumbnails, .candidates, .fullResources, .sizing, .vision]
        let attributed = log.recent(limit: 20_000).compactMap { record -> String? in
            if case .mainThreadBlocked(let ms, let phase) = record.event, let phase, scanPhases.contains(phase) {
                return "\(phase):\(ms)ms"
            }
            return nil
        }
        XCTAssertTrue(attributed.isEmpty, "no >250 ms main-thread block attributed to a scan phase (ambient idle blocks are allowed): \(attributed.prefix(5))")
    }
}
