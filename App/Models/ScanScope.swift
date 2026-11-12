import Foundation

/// Defines different scanning limits for large photo libraries
enum ScanScope: String, CaseIterable, Codable {
    case recent100 = "Recent 100"
    case next1000 = "Next 1,000"
    case start2000 = "Start with 2,000"
    case album = "Select album"
    case all = "Full library" // This should be hidden from user-facing UI
    
    var description: String {
        switch self {
        case .recent100: return "Quick preview scan of recent photos"
        case .next1000: return "Medium scan of next 1,000 photos"
        case .start2000: return "Standard scan of first 2,000 photos"
        case .album: return "Scan a specific album"
        case .all: return "Full library scan (not recommended for large libraries)"
        }
    }
    
    var estimatedTime: String {
        switch self {
        case .recent100: return "~1 minute"
        case .next1000: return "~5 minutes"
        case .start2000: return "~10 minutes" 
        case .album: return "~Varies by album size"
        case .all: return "~Hours (not recommended)"
        }
    }
    
    /// Calculates the maximum number of items to process based on this scan scope
    func calculateMaxItems(for libraryTotal: Int) -> Int {
        switch self {
        case .recent100:
            return min(100, libraryTotal)
        case .next1000:
            return min(1000, libraryTotal)
        case .start2000:
            return min(2000, libraryTotal)
        case .album:
            // For album scanning, we'll process all items in the album
            return libraryTotal
        case .all:
            // For full library scan, process all items
            return libraryTotal
        }
    }
}