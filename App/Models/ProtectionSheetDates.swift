import Foundation

/// Presentation metadata only. One read per distinct asset; never carries deletion authority.
@MainActor
enum ProtectionSheetDates {
    static func load(ids: [String], snapshot: (String) -> PhotoSnapshot?) async -> [String: Date]? {
        var visited: Set<String> = []
        var dates: [String: Date] = [:]
        for id in ids {
            guard !Task.isCancelled else { return nil }
            guard visited.insert(id).inserted else { continue }
            if let date = snapshot(id)?.capturedAt { dates[id] = date }
            if visited.count.isMultiple(of: 25) { await Task.yield() }
        }
        return Task.isCancelled ? nil : dates
    }
}
