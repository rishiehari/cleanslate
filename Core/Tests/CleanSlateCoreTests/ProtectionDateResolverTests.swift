import XCTest
@testable import CleanSlateCore

final class ProtectionDateResolverTests: XCTestCase {
    private func day(_ s: String) -> LocalDay { LocalDay(s)! }
    private func instant(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0, zone: String) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: zone)!
        return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testLocalDayParsingIsStrict() {
        XCTAssertEqual(LocalDay("2026-02-28")?.iso, "2026-02-28")
        for bad in ["2026-02-29", "2026-2-1", "2026/02/01", "20260201", "2026-13-01", "2026-00-10", "2026-04-31", "", "abcd-ef-gh", " 2026-02-01"] {
            XCTAssertNil(LocalDay(bad), bad)
        }
        XCTAssertNotNil(LocalDay("2028-02-29"))
        XCTAssertNil(LocalDay("2100-02-29"))
        XCTAssertNotNil(LocalDay("2000-02-29"))
        XCTAssertTrue(day("2026-01-31") < day("2026-02-01"))
    }

    func testInclusiveEndDay() throws {
        let zone = "America/Los_Angeles"
        let r = try XCTUnwrap(ProtectionDateResolver.interval(start: day("2026-06-10"), end: day("2026-06-12"), timeZoneID: zone))
        XCTAssertEqual(r.start, instant(2026, 6, 10, 0, zone: zone))
        XCTAssertEqual(r.endExclusive, instant(2026, 6, 13, 0, zone: zone))
        let rule = ProtectionRule(scope: .dateRange(start: day("2026-06-10"), end: day("2026-06-12"), timeZoneID: zone,
                                                    startInclusive: r.start, endExclusive: r.endExclusive))
        let set = try ProtectionRuleSet(rules: [rule], revision: 1)
        // 23:59 on the end day is inside; midnight after is outside.
        XCTAssertFalse(set.verdict(ProtectionSubject(id: "x", capturedAt: instant(2026, 6, 12, 23, 59, zone: zone))).allowsRemoval)
        XCTAssertEqual(set.verdict(ProtectionSubject(id: "x", capturedAt: instant(2026, 6, 13, 0, zone: zone))), .unprotected)
        XCTAssertEqual(set.verdict(ProtectionSubject(id: "x", capturedAt: r.start.addingTimeInterval(-1))), .unprotected)
        XCTAssertFalse(set.verdict(ProtectionSubject(id: "x", capturedAt: r.start)).allowsRemoval)
    }

    func testNewYorkFallBack2026_11_01() throws {
        let zone = "America/New_York"   // 25-hour day
        let r = try XCTUnwrap(ProtectionDateResolver.interval(start: day("2026-11-01"), end: day("2026-11-01"), timeZoneID: zone))
        XCTAssertEqual(r.endExclusive.timeIntervalSince(r.start), 25 * 3600)
        XCTAssertEqual(r.start, instant(2026, 11, 1, 0, zone: zone))
        XCTAssertEqual(r.endExclusive, instant(2026, 11, 2, 0, zone: zone))
    }

    func testSpringForward2026_03_08() throws {
        let zone = "America/New_York"   // 23-hour day
        let r = try XCTUnwrap(ProtectionDateResolver.interval(start: day("2026-03-08"), end: day("2026-03-08"), timeZoneID: zone))
        XCTAssertEqual(r.endExclusive.timeIntervalSince(r.start), 23 * 3600)
        XCTAssertEqual(r.endExclusive, instant(2026, 3, 9, 0, zone: zone))
    }

    func testMidnightlessDaySaoPaulo2018_11_04() throws {
        let zone = "America/Sao_Paulo"   // DST began at 00:00, so the first instant of the day is 01:00
        let r = try XCTUnwrap(ProtectionDateResolver.interval(start: day("2018-11-04"), end: day("2018-11-04"), timeZoneID: zone))
        XCTAssertEqual(r.endExclusive.timeIntervalSince(r.start), 23 * 3600)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: zone)!
        XCTAssertEqual(cal.component(.hour, from: r.start), 1)
        XCTAssertEqual(cal.component(.day, from: r.start), 4)
        XCTAssertEqual(cal.component(.day, from: r.endExclusive), 5)
    }

    func testEndBeforeStartRejected() {
        XCTAssertNil(ProtectionDateResolver.interval(start: day("2026-06-12"), end: day("2026-06-10"), timeZoneID: "UTC"))
        let rule = ProtectionRule(scope: .dateRange(start: day("2026-06-12"), end: day("2026-06-10"), timeZoneID: "UTC",
                                                    startInclusive: Date(timeIntervalSince1970: 0), endExclusive: Date(timeIntervalSince1970: 86_400)))
        XCTAssertThrowsError(try ProtectionRuleSet(rules: [rule], revision: 1)) { XCTAssertEqual($0 as? ProtectionRuleSet.Invalid, .endBeforeStart) }
    }

    func testUnknownTimeZoneRejected() {
        XCTAssertNil(ProtectionDateResolver.interval(start: day("2026-06-10"), end: day("2026-06-10"), timeZoneID: "Mars/Olympus"))
        let rule = ProtectionRule(scope: .dateRange(start: day("2026-06-10"), end: day("2026-06-10"), timeZoneID: "Mars/Olympus",
                                                    startInclusive: Date(timeIntervalSince1970: 0), endExclusive: Date(timeIntervalSince1970: 86_400)))
        XCTAssertThrowsError(try ProtectionRuleSet(rules: [rule], revision: 1)) { XCTAssertEqual($0 as? ProtectionRuleSet.Invalid, .unknownTimeZone) }
    }

    func testSameLocalDaysResolveDifferentlyPerZone() throws {
        let a = try XCTUnwrap(ProtectionDateResolver.interval(start: day("2026-06-10"), end: day("2026-06-10"), timeZoneID: "Asia/Tokyo"))
        let b = try XCTUnwrap(ProtectionDateResolver.interval(start: day("2026-06-10"), end: day("2026-06-10"), timeZoneID: "America/New_York"))
        XCTAssertNotEqual(a.start, b.start)
    }
}
