import XCTest
@testable import CleanSlate

/// The Diagnostics screen's plain-words mapping: five summary numbers from a record list,
/// and one human-readable line per event case (counts and durations only).
final class DiagnosticsSummaryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ event: DiagnosticEvent, daysAgo: Double = 0) -> DiagnosticRecord {
        DiagnosticRecord(t: now.addingTimeInterval(-daysAgo * 86_400), event: event)
    }

    // MARK: Summary

    func testSummaryPicksLastScanAndCounts() {
        let records = [
            record(.scanEnded(outcome: .finished, seconds: 42, groupsFound: 6), daysAgo: 10),
            record(.stalled(phase: .vision, secondsSinceProgress: 9, pendingRequests: 1), daysAgo: 8),   // older than 7 days
            record(.scanEnded(outcome: .paused, seconds: 120, groupsFound: 0), daysAgo: 2),
            record(.stalled(phase: .vision, secondsSinceProgress: 7, pendingRequests: 0), daysAgo: 2),
            record(.stalled(phase: .thumbnails, secondsSinceProgress: 12, pendingRequests: 2), daysAgo: 1),
            record(.mainThreadBlocked(ms: 900, phase: .inventory), daysAgo: 1),
            record(.mainThreadBlocked(ms: 300, phase: nil), daysAgo: 0.5),
            record(.memoryWarning(footprintMB: 150), daysAgo: 1),
            record(.appLaunch(version: "1", build: "1", tier: .mid, previousRunEndedCleanly: false, lastPhase: .vision), daysAgo: 3),
            record(.appLaunch(version: "1", build: "1", tier: .mid, previousRunEndedCleanly: true, lastPhase: nil), daysAgo: 0.1),
        ]
        let summary = DiagnosticsSummary(records: records, now: now)
        XCTAssertEqual(summary.lastScanOutcome, .paused)
        XCTAssertEqual(summary.lastScanSeconds, 120)
        XCTAssertEqual(summary.stallsLast7Days, 2, "the 8-day-old stall is outside the window")
        XCTAssertEqual(summary.slowMoments, 2)
        XCTAssertEqual(summary.memoryWarnings, 1)
        XCTAssertEqual(summary.lastUnexpectedStop, now.addingTimeInterval(-3 * 86_400), "clean launches never mask an earlier stop")
    }

    func testEmptyHistoryGivesNeverAndNone() {
        let summary = DiagnosticsSummary(records: [], now: now)
        XCTAssertNil(summary.lastScanOutcome)
        XCTAssertEqual(summary.stallsLast7Days, 0)
        XCTAssertEqual(summary.slowMoments, 0)
        XCTAssertEqual(summary.memoryWarnings, 0)
        XCTAssertNil(summary.lastUnexpectedStop)
    }

    // MARK: Plain-words formatter

    func testFormatterCoversEveryEventCaseWithNoLeftoverPlaceholders() {
        let events = DiagnosticSamples.all
        for event in events {
            let line = event.summaryLine
            XCTAssertFalse(line.isEmpty, "\(event)")
            XCTAssertFalse(line.contains("\\"), "\(event)")   // no unsubstituted template fragments
        }
    }

    func testFormatterUsesOnlyWordsAndNumbersFromTheEvent() {
        // A salted id must never leak into the words (it is the only per-photo field any event carries).
        let event = DiagnosticEvent.requestTimedOut(kind: .thumbnail, asset: SaltedID(value: "deadbeefcafe0001"), seconds: 8)
        XCTAssertFalse(event.summaryLine.contains("deadbeefcafe0001"))
        XCTAssertTrue(event.summaryLine.contains("8"))
    }

    func testSelectedLinesReadInPlainWords() {
        XCTAssertEqual(DiagnosticEvent.governor(decision: .pause, reason: .thermal).summaryLine,
                       "Paused — iPhone is warm")
        XCTAssertEqual(DiagnosticEvent.mainThreadBlocked(ms: 900, phase: .vision).summaryLine,
                       "Screen froze for 900 ms while comparing similar shots")
        XCTAssertEqual(DiagnosticEvent.scanEnded(outcome: .finished, seconds: 65, groupsFound: 6).summaryLine,
                       "Scan finished after 1 min 5 s — 6 group(s) found")
        XCTAssertEqual(DiagnosticEvent.stalled(phase: .thumbnails, secondsSinceProgress: 7, pendingRequests: 1).summaryLine,
                       "No progress while checking photos for 7 s — 1 request(s) pending")
        XCTAssertEqual(DiagnosticEvent.appLaunch(version: "1", build: "2", tier: .high,
                                                 previousRunEndedCleanly: false, lastPhase: .vision).summaryLine,
                       "App reopened after stopping unexpectedly during comparing similar shots")
        XCTAssertEqual(DiagnosticEvent.metricKit(kind: .hang,
                                                 summary: MetricSummary(count: 2, hangDurationMs: 3_000)).summaryLine,
                       "iOS reported a freeze: 2 hang(s), 3 s in total")
        XCTAssertEqual(DiagnosticEvent.scenePhase(state: .background).summaryLine, "App went to the background")
    }
}
