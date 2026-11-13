import Foundation

enum ScanStage: String, CaseIterable {
    case reading
    case comparing
    case grouping
    
    /// Maps from a `ScanPhase` to the corresponding `ScanStage`
    static func from(_ phase: ScanPhase) -> ScanStage {
        switch phase {
        case .inventory, .thumbnails:
            return .reading
        case .candidates, .fullResources, .vision:
            return .comparing
        case .sizing:
            return .grouping
        case .idle, .finished, .cancelled:
            // These cases are for non-scanning states and should not be mapped to progress cards
            return .reading // Default fallback
        }
    }
}