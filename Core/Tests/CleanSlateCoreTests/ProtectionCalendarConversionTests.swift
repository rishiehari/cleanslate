import XCTest
@testable import CleanSlateCore

final class ProtectionCalendarConversionTests: XCTestCase {
    func testBuddhistPickerDateStoresGregorianDay() throws {
        var pickerCalendar = Calendar(identifier: .buddhist)
        pickerCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Bangkok"))
        let selected = try XCTUnwrap(pickerCalendar.date(from: DateComponents(year: 2569, month: 6, day: 10, hour: 12)))
        XCTAssertEqual(ProtectionDateResolver.localDay(containing: selected, timeZoneID: "Asia/Bangkok"), LocalDay("2026-06-10"))
        let day = try XCTUnwrap(ProtectionDateResolver.localDay(containing: selected, timeZoneID: "Asia/Bangkok"))
        let interval = try XCTUnwrap(ProtectionDateResolver.interval(start: day, end: day, timeZoneID: "Asia/Bangkok"))
        XCTAssertTrue(selected >= interval.start && selected < interval.endExclusive)
    }

    func testSameInstantUsesTheRulesTimeZone() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T18:00:00Z"))
        XCTAssertEqual(ProtectionDateResolver.localDay(containing: instant, timeZoneID: "Asia/Tokyo"), LocalDay("2026-06-10"))
        XCTAssertEqual(ProtectionDateResolver.localDay(containing: instant, timeZoneID: "America/New_York"), LocalDay("2026-06-09"))
        XCTAssertNil(ProtectionDateResolver.localDay(containing: instant, timeZoneID: "Unknown/Zone"))
    }

    func testSkippedMidnightDayRoundTripsForDisplay() throws {
        let day = try XCTUnwrap(LocalDay("2018-11-04"))
        let interval = try XCTUnwrap(ProtectionDateResolver.interval(start: day, end: day, timeZoneID: "America/Sao_Paulo"))
        XCTAssertEqual(ProtectionDateResolver.localDay(containing: interval.start, timeZoneID: "America/Sao_Paulo"), day)
    }
}
