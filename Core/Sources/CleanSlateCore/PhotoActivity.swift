import Foundation

/// Metadata-only activity hints. Counts do not establish duplicate content or reclaimable bytes.
public struct PhotoActivityPeriod: Identifiable, Equatable, Sendable {
    public var id: Date { start }
    public let start: Date
    public let end: Date
    public let itemCount: Int
    public let burstPhotoCount: Int
}

public struct PhotoActivitySummary: Equatable, Sendable {
    public let sampledCount: Int
    public let sampleLimit: Int
    public let periods: [PhotoActivityPeriod]
    public var reachedLimit: Bool { sampledCount >= sampleLimit }
}

/// Accepts only dates and burst membership; retains no photo identifiers, locations or image bytes.
public struct PhotoActivityBuilder: Sendable {
    private let calendar: Calendar
    private let sampleLimit: Int
    private var count = 0
    private var weeks: [Date: (end: Date, items: Int, bursts: Int)] = [:]

    public init(calendar: Calendar = .current, sampleLimit: Int = 5_000) {
        self.calendar = calendar
        self.sampleLimit = max(1, sampleLimit)
    }

    public mutating func add(date: Date?, isBurst: Bool) {
        guard count < sampleLimit else { return }
        count += 1
        guard let date, let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return }
        let previous = weeks[week.start] ?? (week.end, 0, 0)
        weeks[week.start] = (week.end, previous.items + 1, previous.bursts + (isBurst ? 1 : 0))
    }

    public func finish() -> PhotoActivitySummary {
        let periods = weeks.map { start, values in
            PhotoActivityPeriod(start: start, end: values.end, itemCount: values.items, burstPhotoCount: values.bursts)
        }.sorted {
            if $0.burstPhotoCount != $1.burstPhotoCount { return $0.burstPhotoCount > $1.burstPhotoCount }
            if $0.itemCount != $1.itemCount { return $0.itemCount > $1.itemCount }
            return $0.start > $1.start
        }
        return PhotoActivitySummary(sampledCount: count, sampleLimit: sampleLimit, periods: Array(periods.prefix(3)))
    }
}
