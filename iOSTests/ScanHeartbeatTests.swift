import XCTest
@testable import CleanSlate

/// The heartbeat writes one `heartbeat` event per beat and a `stalled` event when `done` stops moving.
/// Time and probes are injected so no real timer, clock or memory probe is needed.
final class ScanHeartbeatTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("heartbeat-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeLog() -> DiagnosticsLog { DiagnosticsLog(directory: dir) }

    private func probes(clock: TestClock, footprintMB: Int = 80, availableMB: Int = 900, thermal: Int = 1,
                        lowPower: Bool = false) -> ScanHeartbeat.Probes {
        ScanHeartbeat.Probes(footprintMB: { footprintMB }, availableMB: { availableMB }, thermal: { thermal },
                             lowPower: { lowPower }, seconds: { clock.now })
    }

    func testBeatEmitsHeartbeatWithCounterAndProbeFields() {
        let log = makeLog()
        let counters = ScanCounters()
        counters.update { $0.phase = .vision; $0.done = 40; $0.total = 100; $0.inFlight = 2; $0.thumbsTried = 10; $0.thumbsUnavailable = 3 }
        let clock = TestClock()
        clock.now = 1_000
        let heartbeat = ScanHeartbeat(log: log, counters: counters,
                                      probes: probes(clock: clock, footprintMB: 55, availableMB: 700, thermal: 2, lowPower: true))
        heartbeat.beat()
        XCTAssertEqual(log.recent(limit: 10).map(\.event),
                       [.heartbeat(phase: .vision, done: 40, total: 100, footprintMB: 55, availableMB: 700, thermal: 2,
                                   lowPower: true, inFlight: 2, thumbsTried: 10, thumbsUnavailable: 3)])
    }

    func testStalledIsEmittedOnceDoneStopsMovingForSixSeconds() {
        let log = makeLog()
        let counters = ScanCounters()
        counters.update { $0.phase = .thumbnails; $0.done = 5; $0.total = 100; $0.inFlight = 1 }
        let clock = TestClock()
        let heartbeat = ScanHeartbeat(log: log, counters: counters, probes: probes(clock: clock), stallAfter: 6)
        heartbeat.beat()                       // establishes the baseline at t=0
        clock.now = 3; heartbeat.beat()        // 3 s without progress: not a stall yet
        XCTAssertEqual(log.recent(limit: 10).compactMap { if case .stalled = $0.event { $0 } else { nil } }.count, 0)
        clock.now = 7; heartbeat.beat()        // 7 s without progress: stalled
        clock.now = 9; heartbeat.beat()        // still no progress: reported again with the longer gap
        let stalled = log.recent(limit: 10).compactMap { record -> DiagnosticEvent? in
            if case .stalled = record.event { return record.event }
            return nil
        }
        XCTAssertEqual(stalled, [.stalled(phase: .thumbnails, secondsSinceProgress: 7, pendingRequests: 1),
                                 .stalled(phase: .thumbnails, secondsSinceProgress: 9, pendingRequests: 1)])
    }

    func testNoStallWhileProgressMoves() {
        let log = makeLog()
        let counters = ScanCounters()
        counters.update { $0.phase = .inventory; $0.total = 10_000 }
        let clock = TestClock()
        let probes = ScanHeartbeat.Probes(footprintMB: { 80 }, availableMB: { 900 }, thermal: { 0 },
                                          lowPower: { false }, seconds: { clock.now })
        let heartbeat = ScanHeartbeat(log: log, counters: counters, probes: probes, stallAfter: 6)
        for _ in 0..<5 {                        // beats 10 s apart (beyond stallAfter) but done keeps moving
            clock.now += 10
            counters.update { $0.done += 25 }
            heartbeat.beat()
        }
        XCTAssertEqual(log.recent(limit: 100).count, 5, "only heartbeats, no stall events")
        XCTAssertTrue(log.recent(limit: 100).allSatisfy { if case .heartbeat = $0.event { true } else { false } })
    }
}
