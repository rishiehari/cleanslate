import Foundation

/// Product scans are bounded. `all` is internal regression/maintenance coverage only.
enum ScanScope: String, CaseIterable, Codable, Sendable {
    case activityRange = "Suggested week"
    case recentMonth = "Past month"
    case recentTwoMonths = "Past two months"
    case recent100 = "Recent 100"
    case next1000 = "Next 1,000"
    case start2000 = "Start with 2,000"
    case album = "Select album"
    case all = "Full library"

    static let userScopes: [ScanScope] = [.recentMonth, .recentTwoMonths, .recent100, .next1000, .start2000]
    var title: String { self == .next1000 ? "Latest 1,000" : self == .start2000 ? "Latest 2,000" : rawValue }
    var description: String {
        switch self {
        case .activityRange: "A busy week from your activity overview. Up to 2,000 items."
        case .recentMonth: "Photos and videos from the past month, newest first. Up to 2,000 items."
        case .recentTwoMonths: "Photos and videos from the past two months, newest first. Up to 2,000 items."
        case .recent100: "Quick preview scan of recent photos"
        case .next1000: "Medium scan of next 1,000 photos"
        case .start2000: "Standard scan of first 2,000 photos"
        case .album: "Scan a specific album"
        case .all: "Full library scan (not recommended for large libraries)"
        }
    }

    var maximumItems: Int? {
        switch self {
        case .recent100: 100
        case .next1000: 1_000
        case .activityRange, .recentMonth, .recentTwoMonths, .start2000: 2_000
        case .all, .album: nil
        }
    }

    func calculateMaxItems(for libraryTotal: Int) -> Int { min(maximumItems ?? max(0, libraryTotal), max(0, libraryTotal)) }

    func inventoryRequest(now: Date = Date(), calendar: Calendar = .current) -> ScanInventoryRequest {
        let months = self == .recentMonth ? 1 : self == .recentTwoMonths ? 2 : 0
        return ScanInventoryRequest(maximumItems: maximumItems,
            earliestDate: months > 0 ? calendar.date(byAdding: .month, value: -months, to: now) : nil,
            latestDate: months > 0 ? now : nil)
    }
}

struct ScanInventoryRequest: Sendable, Equatable {
    let maximumItems: Int?
    let earliestDate: Date?
    let latestDate: Date?

    func includes(_ photo: PhotoSnapshot) -> Bool {
        guard earliestDate != nil || latestDate != nil else { return true }
        guard let date = photo.capturedAt else { return false }
        return (earliestDate.map { date >= $0 } ?? true) && (latestDate.map { date <= $0 } ?? true)
    }
}

struct ScanInventoryPage: Sendable {
    let photos: [PhotoSnapshot]
    let total: Int
}
