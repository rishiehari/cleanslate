import XCTest
import SwiftUI
@testable import CleanSlate

/// `appLaunch` reports a leftover `scan.inProgress` marker as a previous run that did not end cleanly
/// (killed mid-scan), and scene phase changes log `.scenePhase`.
final class DiagnosticsLaunchTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("launch-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeLog() -> DiagnosticsLog { DiagnosticsLog(directory: dir) }

    func testMarkerLeftByKilledScanIsReportedAsUncleanLaunch() async throws {
        let store = try LibraryStore(path: nil)
        let log = makeLog()
        await ScanInProgressMarker.set(.vision, in: store)      // a scan was killed during the Vision phase
        await DiagnosticsLaunch.recordAppLaunch(store: store, log: log)
        let events = log.recent(limit: 10).map(\.event)
        guard case .appLaunch(let version, let build, _, let clean, let lastPhase) = events.first else {
            return XCTFail("expected appLaunch, got \(events)")
        }
        XCTAssertFalse(version.isEmpty); XCTAssertFalse(build.isEmpty)
        XCTAssertFalse(clean, "a leftover marker means the previous run did not end cleanly")
        XCTAssertEqual(lastPhase, .vision)
        let leftover = await ScanInProgressMarker.read(in: store)
        XCTAssertNil(leftover, "the marker is consumed once reported")
    }

    func testCleanLaunchHasNoLastPhase() async throws {
        let store = try LibraryStore(path: nil)
        let log = makeLog()
        await DiagnosticsLaunch.recordAppLaunch(store: store, log: log)
        let events = log.recent(limit: 10).map(\.event)
        guard case .appLaunch(_, _, _, let clean, let lastPhase) = events.first else {
            return XCTFail("expected appLaunch, got \(events)")
        }
        XCTAssertTrue(clean)
        XCTAssertNil(lastPhase)
    }

    func testScenePhaseMapping() {
        XCTAssertEqual(DiagScene(.active), .active)
        XCTAssertEqual(DiagScene(.inactive), .inactive)
        XCTAssertEqual(DiagScene(.background), .background)
    }

    /// Spec: events flush every 5 s or on background. The background hook must push buffered
    /// events to disk so a fresh log instance over the same directory sees them.
    func testBackgroundHookFlushesBufferedEventsToDisk() {
        let log = makeLog()
        for n in 0..<10 { log.record(.progress(phase: .inventory, done: n, total: 10)) }
        DiagnosticsHooks.didEnterBackground(log: log)
        let onDisk = DiagnosticsLog(directory: dir).recent(limit: 20)   // a new instance reads only files
        XCTAssertEqual(onDisk.count, 10, "the background hook flushed the buffer")
    }
}
