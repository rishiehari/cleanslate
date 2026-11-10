import XCTest
@testable import CleanSlate

/// The watchdog records `mainThreadBlocked` only above the 250 ms threshold and at most once per 5 s.
/// Latency and clock are injected, so no real main-thread blocking is needed.
final class MainThreadWatchdogTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("watchdog-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeLog() -> DiagnosticsLog { DiagnosticsLog(directory: dir) }

    private func watchdog(log: DiagnosticsLog, latency: Int, clock: Double, phase: DiagPhase? = nil) -> MainThreadWatchdog {
        MainThreadWatchdog(log: log, probes: .init(latencyMs: { latency }, now: { clock }, phase: { phase }))
    }

    func testLatencyAboveThresholdRecordsMainThreadBlocked() {
        let log = makeLog()
        watchdog(log: log, latency: 900, clock: 1_000).check()
        XCTAssertEqual(log.recent(limit: 5).map(\.event), [.mainThreadBlocked(ms: 900, phase: nil)])
    }

    func testLatencyAtOrBelowThresholdRecordsNothing() {
        let log = makeLog()
        watchdog(log: log, latency: 250, clock: 1_000).check()
        watchdog(log: log, latency: 100, clock: 1_001).check()
        XCTAssertTrue(log.recent(limit: 5).isEmpty)
    }

    func testCurrentPhaseIsAttached() {
        let log = makeLog()
        watchdog(log: log, latency: 600, clock: 1_000, phase: .fullResources).check()
        XCTAssertEqual(log.recent(limit: 5).map(\.event), [.mainThreadBlocked(ms: 600, phase: .fullResources)])
    }

    func testThrottlesToOneEventPerFiveSeconds() {
        let log = makeLog()
        let clock = TestClock()
        let watchdog = MainThreadWatchdog(log: log, probes: .init(latencyMs: { 500 }, now: { clock.now }))
        clock.now = 0; watchdog.check()
        clock.now = 2; watchdog.check()          // within 5 s of the first event: dropped
        clock.now = 4; watchdog.check()          // still within 5 s: dropped
        clock.now = 6; watchdog.check()          // 6 s later: recorded
        XCTAssertEqual(log.recent(limit: 5).map(\.event),
                       [.mainThreadBlocked(ms: 500, phase: nil), .mainThreadBlocked(ms: 500, phase: nil)])
    }
}
