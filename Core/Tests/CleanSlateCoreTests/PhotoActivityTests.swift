import XCTest
@testable import CleanSlateCore

final class PhotoActivityTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 2
        return value
    }

    func testBurstHeavyWeekRanksAboveHigherVolumeWeek() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var builder = PhotoActivityBuilder(calendar: calendar)
        for _ in 0..<50 { builder.add(date: date, isBurst: false) }
        let other = calendar.date(byAdding: .day, value: -14, to: date)!
        for _ in 0..<12 { builder.add(date: other, isBurst: true) }
        let summary = builder.finish()
        XCTAssertEqual(summary.sampledCount, 62)
        XCTAssertEqual(summary.periods.first?.itemCount, 12)
        XCTAssertEqual(summary.periods.first?.burstPhotoCount, 12)
        XCTAssertLessThanOrEqual(summary.periods.count, 3)
    }

    func testOverviewCapAndUnknownDatesAreHonest() {
        var builder = PhotoActivityBuilder(calendar: calendar, sampleLimit: 5)
        builder.add(date: nil, isBurst: false)
        for _ in 0..<20 { builder.add(date: Date(timeIntervalSince1970: 1_800_000_000), isBurst: true) }
        let summary = builder.finish()
        XCTAssertEqual(summary.sampledCount, 5)
        XCTAssertTrue(summary.reachedLimit)
        XCTAssertEqual(summary.periods.reduce(0) { $0 + $1.itemCount }, 4)
    }

    func testWeekIntervalsDoNotOverlapAndNewestBreaksTies() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var builder = PhotoActivityBuilder(calendar: calendar)
        for days in [0, -7, -14, -21] { builder.add(date: calendar.date(byAdding: .day, value: days, to: date), isBurst: false) }
        let periods = builder.finish().periods
        XCTAssertEqual(periods.count, 3)
        XCTAssertGreaterThan(periods[0].start, periods[1].start)
        XCTAssertGreaterThanOrEqual(periods[0].start, periods[1].end)
    }
}
