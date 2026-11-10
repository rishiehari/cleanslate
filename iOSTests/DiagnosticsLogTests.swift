import XCTest
@testable import CleanSlate

/// Sample of every event case, used to check the allow-list and round-tripping.
enum DiagnosticSamples {
    static let all: [DiagnosticEvent] = [
        .appLaunch(version: "1.0", build: "7", tier: .mid, previousRunEndedCleanly: false, lastPhase: .thumbnails),
        .scenePhase(state: .background),
        .scanStarted(scope: .all, items: 7_938),
        .phaseEntered(phase: .inventory, units: 7_938),
        .phaseEnded(phase: .inventory, millis: 1_200, done: 7_938, total: 7_938),
        .progress(phase: .thumbnails, done: 25, total: 7_938),
        .thumbnailStats(tried: 7_168, unavailable: 7_146, unavailablePercent: 99),
        .heartbeat(phase: .vision, done: 10, total: 100, footprintMB: 80, availableMB: 900, thermal: 1, lowPower: true,
                   inFlight: 1, thumbsTried: 5, thumbsUnavailable: 2),
        .stalled(phase: .vision, secondsSinceProgress: 12, pendingRequests: 1),
        .requestTimedOut(kind: .thumbnail, asset: SaltedID(value: "0123456789abcdef"), seconds: 8),
        .mainThreadBlocked(ms: 900, phase: .inventory),
        .governor(decision: .pause, reason: .thermal),
        .memoryWarning(footprintMB: 150),
        .scanEnded(outcome: .finished, seconds: 42, groupsFound: 6),
        .metricKit(kind: .hang, summary: MetricSummary(count: 1, hangDurationMs: 3_000, peakMemoryMB: 200, cpuTimeMs: 10))
    ]
}

final class DiagnosticsLogTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDown() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }

    private func files() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "jsonl" }
    }

    func testRecordsRoundTripThroughDiskInOrder() {
        let log = DiagnosticsLog(directory: dir)
        DiagnosticSamples.all.forEach(log.record)
        XCTAssertEqual(log.recent(limit: 100).map(\.event), DiagnosticSamples.all)
        XCTAssertEqual(log.recent(limit: 3).map(\.event), Array(DiagnosticSamples.all.suffix(3)))
        // A fresh instance over the same directory sees the same data (it was really written).
        XCTAssertEqual(DiagnosticsLog(directory: dir).recent(limit: 100).count, DiagnosticSamples.all.count)
    }

    func testEveryJSONKeyIsOnTheAllowList() throws {
        let log = DiagnosticsLog(directory: dir)
        DiagnosticSamples.all.forEach(log.record)
        let data = try Data(contentsOf: log.exportFile())
        var keys: Set<String> = []
        func collect(_ value: Any) {
            if let object = value as? [String: Any] { for (key, inner) in object { keys.insert(key); collect(inner) } }
            else if let array = value as? [Any] { array.forEach(collect) }
        }
        for line in data.split(separator: 0x0A) { collect(try JSONSerialization.jsonObject(with: Data(line))) }
        XCTAssertFalse(keys.isEmpty)
        XCTAssertTrue(keys.isSubset(of: DiagnosticEvent.allowedKeys), "unexpected keys: \(keys.subtracting(DiagnosticEvent.allowedKeys))")
    }

    func testRotationKeepsAtMostTwoFilesAndOneMegabyte() {
        let log = DiagnosticsLog(directory: dir)
        var written = 0
        for n in 0..<14_000 {
            log.record(.heartbeat(phase: .vision, done: n, total: 20_000, footprintMB: 100, availableMB: 800, thermal: 0, lowPower: false,
                                  inFlight: 1, thumbsTried: n, thumbsUnavailable: 0))
            written += 1
        }
        log.flush()
        XCTAssertLessThanOrEqual(files().count, 2)
        XCTAssertGreaterThan(log.bytesOnDisk(), 0)
        XCTAssertLessThanOrEqual(log.bytesOnDisk(), 1_048_576)
        let kept = log.recent(limit: 100_000)
        XCTAssertLessThan(kept.count, written, "the oldest events were rotated out")
        guard case .heartbeat(_, let lastDone, _, _, _, _, _, _, _, _) = kept.last?.event else { return XCTFail("no events") }
        XCTAssertEqual(lastDone, 13_999, "the newest event is kept")
    }

    func testDeleteRemovesFilesAndRotatesTheSalt() throws {
        let log = DiagnosticsLog(directory: dir)
        let before = log.salted("x")
        XCTAssertEqual(log.salted("x"), before, "stable between calls")
        log.record(.scenePhase(state: .active)); log.flush()
        XCTAssertFalse(files().isEmpty)
        try log.deleteAll()
        XCTAssertTrue(files().isEmpty)
        XCTAssertTrue(log.recent(limit: 10).isEmpty)
        XCTAssertNotEqual(log.salted("x"), before)
        XCTAssertEqual(DiagnosticsLog(directory: dir).salted("x"), log.salted("x"), "the new salt is persisted")
        XCTAssertEqual(log.salted("x").value.count, 16)
        XCTAssertFalse(log.salted("x").value.contains("x"))
    }

    func testThousandConcurrentRecordsLoseNothing() {
        let log = DiagnosticsLog(directory: dir)
        DispatchQueue.concurrentPerform(iterations: 1_000) { n in log.record(.progress(phase: .thumbnails, done: n, total: 1_000)) }
        let done = log.recent(limit: 5_000).compactMap { record -> Int? in
            if case .progress(_, let done, _) = record.event { return done }
            return nil
        }
        XCTAssertEqual(Set(done), Set(0..<1_000))
        XCTAssertEqual(done.count, 1_000)
    }

    func testUnwritableDirectoryDisablesTheLogSilently() throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("diag-blocker-\(UUID().uuidString)")
        try Data("x".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let log = DiagnosticsLog(directory: blocker.appendingPathComponent("sub"))      // a file where a folder is needed
        XCTAssertFalse(log.isEnabled)
        log.record(.scenePhase(state: .active)); log.flush()
        XCTAssertTrue(log.recent(limit: 10).isEmpty)
        XCTAssertNoThrow(try log.exportFile())
        XCTAssertFalse(DiagnosticsLog(directory: nil).isEnabled)
    }

    func testAWriteFailureAfterStartDisablesTheLogWithoutCrashing() throws {
        let log = DiagnosticsLog(directory: dir)
        log.record(.scenePhase(state: .active)); log.flush()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)       // disk-full style failure
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: dir.appendingPathComponent("diag-0.jsonl").path)
        log.record(.scenePhase(state: .background)); log.flush()
        XCTAssertFalse(log.isEnabled)
        log.record(.scenePhase(state: .active)); log.flush()       // still no crash
    }

    func testAClockGoingBackwardsDoesNotReorderOrDropEvents() {
        let ticks = OSAllocatedCounter()
        let log = DiagnosticsLog(directory: dir, now: { Date(timeIntervalSince1970: 1_000_000 - Double(ticks.next())) })
        for n in 0..<10 { log.record(.progress(phase: .inventory, done: n, total: 10)) }
        let kept = log.recent(limit: 100)
        XCTAssertEqual(kept.count, 10)
        XCTAssertEqual(kept.compactMap { if case .progress(_, let d, _) = $0.event { d } else { nil } }, Array(0..<10))
    }

    func testLogIsExcludedFromBackup() throws {
        _ = DiagnosticsLog(directory: dir)
        let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }
}

import os
final class OSAllocatedCounter: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)
    func next() -> Int { lock.withLock { $0 += 1; return $0 } }
}
