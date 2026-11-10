import Foundation

/// Coarse device class from physical memory. Budgets are from docs/FEATURE_ROADMAP.md ("Shared device-tier budgets").
enum DeviceTier: String, Codable, Sendable {
    case low, mid, high

    static let lowCeiling: UInt64 = 3_758_096_384      // < 3.5 GB
    static let midCeiling: UInt64 = 5_905_580_032      // < 5.5 GB

    /// "L", "M" or "H" (how docs and `make budget` name the tiers).
    var letter: String {
        switch self { case .low: "L"; case .mid: "M"; case .high: "H" }
    }

    /// Peak `phys_footprint` allowed during any scan, in MB.
    var peakBudgetMB: Double {
        switch self { case .low: 120; case .mid: 160; case .high: 200 }
    }

    /// `physicalMemory` is injectable for tests. `CLEANSLATE_TIER` (L/M/H) in `environment` wins: a simulator reports the
    /// Mac's RAM, so `make budget` states which device it stands in for.
    static func resolve(physicalMemory: UInt64, environment: [String: String] = [:]) -> DeviceTier {
        if let forced = environment["CLEANSLATE_TIER"]?.uppercased() {
            switch forced { case "L": return .low; case "M": return .mid; case "H": return .high; default: break }
        }
        if physicalMemory < lowCeiling { return .low }
        if physicalMemory < midCeiling { return .mid }
        return .high
    }

    static var current: DeviceTier {
        resolve(physicalMemory: ProcessInfo.processInfo.physicalMemory, environment: ProcessInfo.processInfo.environment)
    }
}
