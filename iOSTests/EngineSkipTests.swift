import XCTest
import CleanSlateCore
@testable import CleanSlate

/// F03.8: the heartbeat exposes secondsSinceBeat / isStalled / onStall, and skipping a stage
/// ends it early — exact groups found earlier stay intact and nothing is marked as matched.
@MainActor
final class EngineSkipTests: XCTestCase {
    private func waitUntil(timeout: TimeInterval, poll: Duration = .milliseconds(50), _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: poll)
        }
        return condition()
    }

    func testStallStateMachineSurfacesSecondsIsStalledAndCallback() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hb-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = DiagnosticsLog(directory: dir)
        let counters = ScanCounters()
        counters.update { $0.phase = .thumbnails; $0.done = 5; $0.total = 100; $0.inFlight = 1 }
        let clock = TestClock()
        let stalls = StallBox()
        let heartbeat = ScanHeartbeat(log: log, counters: counters,
                                      probes: .init(footprintMB: { 80 }, availableMB: { 900 }, thermal: { 0 }, lowPower: { false },
                                                    seconds: { clock.now }),
                                      stallAfter: 6)
        heartbeat.onStall = { stalls.values.append($0) }
        let stallEnds = StallBox()
        heartbeat.onStallEnd = { stallEnds.values.append(0) }
        heartbeat.beat()
        XCTAssertFalse(heartbeat.isStalled)
        clock.now = 7; heartbeat.beat()
        XCTAssertTrue(heartbeat.isStalled, "a stall episode is open")
        XCTAssertEqual(heartbeat.secondsSinceBeat, 7, accuracy: 0.001)
        XCTAssertEqual(stalls.values, [7], "onStall fires once per episode")
        clock.now = 9; heartbeat.beat()
        XCTAssertEqual(stalls.values, [7], "no stream of events while frozen")
        counters.update { $0.done = 6; $0.inFlight = 0 }     // movement re-arms
        clock.now = 10; heartbeat.beat()
        XCTAssertFalse(heartbeat.isStalled)
        clock.now = 17; heartbeat.beat()
        XCTAssertEqual(stalls.values, [7, 7], "a new episode fires again")
        XCTAssertTrue(heartbeat.isStalled)
    }

    func testSkipComparingKeepsExactGroupsAndMarksNothing() async throws {
        let library = FakePhotoLibrary()
        library.add("ex-a", content: "identical", bytes: 5_000, at: 500)
        library.add("ex-b", content: "identical", bytes: 5_000, at: 500)
        let spec = FakePhotoLibrary.RenderSpec(base: 5)
        library.add("sim-a", content: "a", at: 1_000_000, spec: spec)
        library.add("sim-b", content: "b", at: 9_000_000, spec: spec)
        let visual = FakeVisualAnalyzer()
        visual.delayPerCall = .milliseconds(25)             // keeps the Comparing phase open long enough to skip
        let model = try ScanTestRig.model(library: library, visual: visual)
        model.scanAllForTesting()
        let reachedComparing = await waitUntil(timeout: 30) { model.scanCounters.snapshot.phase == .vision }
        XCTAssertTrue(reachedComparing, "the scan reached the Comparing phase")
        model.skipCurrentStage()
        let done = await waitUntil(timeout: 30) { !model.isScanning }
        XCTAssertTrue(done, "the scan finished after the skip")
        XCTAssertEqual(model.statistics.stagesSkipped, [.vision])
        XCTAssertEqual(model.groups.filter { $0.kind == .exact }.count, 1, "exact groups found earlier are intact")
        XCTAssertTrue(model.groups.filter { $0.kind == .similar }.isEmpty, "skipping Comparing marked nothing")
    }

    func testSkipWhileIdleIsIgnoredAndNotConsumed() async throws {
        let library = FakePhotoLibrary()
        for i in 0..<20 { library.add("p\(i)", content: "c\(i)") }
        let model = try ScanTestRig.model(library: library)
        model.skipCurrentStage()                    // no scan running: ignored, NOT consumed
        await model.runScan()
        XCTAssertEqual(model.statistics.photosEnumerated, 20, "the scan ran normally")
        XCTAssertTrue(model.statistics.stagesSkipped.isEmpty, "an idle skip must not be consumed by the next scan")
        XCTAssertEqual(model.phase, .finished)
    }

    func testSkipMidInventoryEndsAsCancelledNotFinishedOverZero() async throws {
        let library = FakePhotoLibrary()
        for i in 0..<2_500 { library.add("p\(i)", content: "c\(i)") }
        let model = try ScanTestRig.model(library: library)
        var skipped = false
        library.onInventoryPage = { offset in
            if offset == 1_000, !skipped { skipped = true; model.skipCurrentStage() }
        }
        await model.runScan()          // deterministic: the hook fires inside the awaited scan
        XCTAssertEqual(model.statistics.stagesSkipped, [.inventory])
        XCTAssertEqual(model.phase, .cancelled, "a skipped inventory ends as paused, not finished")
        XCTAssertLessThan(model.statistics.photosEnumerated, 2_500, "no finished-over-partial claim")
        XCTAssertTrue(model.statusMessage?.lowercased().contains("paused") ?? false, "the message says the progress is saved")
    }

    private final class StallBox: @unchecked Sendable { var values: [Int] = [] }
}
