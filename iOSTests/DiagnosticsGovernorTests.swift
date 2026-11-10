import XCTest
import UIKit
@testable import CleanSlate

/// The two event cases that F02 defines but nothing recorded (edge findings m8):
/// system memory warnings and resource-governor decisions.
@MainActor
final class DiagnosticsGovernorTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("governor-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeLog() -> DiagnosticsLog { DiagnosticsLog(directory: dir) }

    private func governor(thermal: ProcessInfo.ThermalState, memoryBytes: Int = 1_000_000_000,
                          lowPower: Bool = false, maximumPauseSeconds: Int = 0) -> ResourceGovernor {
        ResourceGovernor(inputs: .init(thermalState: { thermal }, availableMemoryBytes: { memoryBytes },
                                       lowPowerMode: { lowPower }, sleep: { _ in }),
                         cores: 8, maximumPauseSeconds: maximumPauseSeconds)
    }

    func testStopAndShrinkDecisionsAreRecordedOncePerChange() async {
        let log = makeLog()
        let critical = governor(thermal: .critical)
        critical.diagnostics = log
        _ = await critical.checkpoint()
        _ = await critical.checkpoint()          // unchanged decision: stays silent
        let fair = governor(thermal: .fair)
        fair.diagnostics = log
        _ = await fair.checkpoint()              // thermal throttling -> shrink
        let hot = governor(thermal: .serious, maximumPauseSeconds: 2)
        hot.diagnostics = log
        _ = await hot.checkpoint()               // waits, then gives up -> stop
        let events = log.recent(limit: 20).map(\.event)
        XCTAssertEqual(events, [.governor(decision: .stop, reason: .thermal),
                                .governor(decision: .shrink, reason: .thermal),
                                .governor(decision: .pause, reason: .thermal),
                                .governor(decision: .stop, reason: .thermal)])
    }

    func testLowMemoryAndLowPowerShrinkDecisions() async {
        let log = makeLog()
        let lowMemory = governor(thermal: .nominal, memoryBytes: 1)
        lowMemory.diagnostics = log
        _ = await lowMemory.checkpoint()
        let lowPower = governor(thermal: .nominal, lowPower: true)
        lowPower.diagnostics = log
        _ = await lowPower.checkpoint()
        XCTAssertEqual(log.recent(limit: 10).map(\.event),
                       [.governor(decision: .shrink, reason: .lowMemory),
                        .governor(decision: .shrink, reason: .lowPower)])
    }

    func testFullSpeedProceedRecordsNoEvent() async {
        let log = makeLog()
        let nominal = governor(thermal: .nominal)
        nominal.diagnostics = log
        for _ in 0..<3 { _ = await nominal.checkpoint() }
        XCTAssertTrue(log.recent(limit: 10).isEmpty, "no decision, no event")
    }

    func testMemoryWarningNotificationRecordsFootprint() {
        let log = makeLog()
        let token = DiagnosticsHooks.observeMemoryWarnings(log: log)
        defer { NotificationCenter.default.removeObserver(token) }
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        let events = log.recent(limit: 5).map(\.event)
        guard case .memoryWarning(let footprint)? = events.first else { return XCTFail("expected memoryWarning, got \(events)") }
        XCTAssertGreaterThan(footprint, 0, "a real footprint number")
    }
}
