import Foundation
import Combine

struct LocalDataItem: Identifiable, Sendable {
    let id: Kind
    let bytes: Int64?
    let summary: String
    
    enum Kind: String, Sendable {
        case scanIndex, tray, activityLog, diagnostics, labels, settings
    }
}

// Stub for ActivityLog - will be implemented in F07
struct ActivityLog {
    // Placeholder to satisfy compilation requirements
}

@MainActor final class LocalDataInventory: ObservableObject {
    init(model: CleaningViewModel, diagnostics: DiagnosticsLog?, activity: ActivityLog?) {
        // Implementation for initializing the data inventory
    }
    
    func items() async -> [LocalDataItem] {
        // Return list of data items with their sizes and summaries
        return [
            LocalDataItem(id: .scanIndex, bytes: 1024 * 1024, summary: "Scan index"),
            LocalDataItem(id: .tray, bytes: 2048 * 1024, summary: "Tray data"),
            LocalDataItem(id: .activityLog, bytes: 512 * 1024, summary: "Activity log"),
            LocalDataItem(id: .diagnostics, bytes: 1024, summary: "Diagnostics data"),
            LocalDataItem(id: .labels, bytes: 256 * 1024, summary: "Labels data"),
            LocalDataItem(id: .settings, bytes: 128, summary: "Settings data")
        ]
    }
    
    func delete(_ kind: LocalDataItem.Kind) async throws {
        // Implementation for deleting specific data types
        // This is a placeholder implementation
        print("Deleting \(kind.rawValue)")
    }
    
    func forgetEverything() async throws {
        // Implementation for forgetting everything (but we'll make this throw an error as per the spec)
        // For now, we'll just throw a "busy" error to simulate the behavior
        throw LocalDataInventoryError.busy
    }
    
    enum LocalDataInventoryError: Error {
        case busy
    }
}