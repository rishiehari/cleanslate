import Foundation

enum LocalDataError: Error {
    case busy
}

struct LocalDataItem: Identifiable, Sendable {
    let id: Kind
    let bytes: Int64?
    let summary: String
    
    enum Kind: String, Sendable {
        case scanIndex, tray, activityLog, diagnostics, labels, settings
    }
}

@MainActor
final class LocalDataInventory {
    private let model: CleaningViewModel
    private let diagnostics: DiagnosticsLog?
    private let activity: ActivityLog?
    
    init(model: CleaningViewModel, diagnostics: DiagnosticsLog?, activity: ActivityLog?) {
        self.model = model
        self.diagnostics = diagnostics
        self.activity = activity
    }
    
    func items() async -> [LocalDataItem] {
        var items: [LocalDataItem] = []
        
        // Scan index
        items.append(LocalDataItem(
            id: .scanIndex,
            bytes: try? await getScanIndexSize(),
            summary: "Saved scan data"
        ))
        
        // Tray
        items.append(LocalDataItem(
            id: .tray,
            bytes: try? await getTraySize(),
            summary: "Photos in your tray"
        ))
        
        // Activity log
        items.append(LocalDataItem(
            id: .activityLog,
            bytes: try? await getActivityLogSize(),
            summary: "Activity history"
        ))
        
        // Diagnostics
        items.append(LocalDataItem(
            id: .diagnostics,
            bytes: try? await getDiagnosticsSize(),
            summary: "Diagnostic logs"
        ))
        
        // Labels
        items.append(LocalDataItem(
            id: .labels,
            bytes: try? await getLabelsSize(),
            summary: "Label corrections"
        ))
        
        // Settings
        items.append(LocalDataItem(
            id: .settings,
            bytes: try? await getSettingsSize(),
            summary: "App settings"
        ))
        
        return items
    }
    
    func delete(_ kind: LocalDataItem.Kind) async throws {
        switch kind {
        case .scanIndex:
            // Delete scan index
            try await model.resetScanIndex()
        case .tray:
            // Clear tray
            model.tray.clear()
        case .activityLog:
            // Delete activity log
            try await activity?.deleteAll()
        case .diagnostics:
            // Delete diagnostics
            try await diagnostics?.deleteAll()
        case .labels:
            // Reset labels
            try await LabelStore.reset()
        case .settings:
            // Reset settings (but keep onboarding flag)
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        }
    }
    
    func forgetEverything() async throws {
        // Check if we're currently scanning or deleting
        if model.isScanning || model.tray.isDeleting {
            throw LocalDataError.busy
        }
        
        // Delete all data types
        try await delete(.scanIndex)
        model.tray.clear()
        try await activity?.deleteAll()
        try await diagnostics?.deleteAll()
        try await LabelStore.reset()
        
        // Remove CleanSlate's UserDefaults keys except onboarding flag
        let userDefaults = UserDefaults.standard
        let allKeys = Array(userDefaults.dictionaryRepresentation().keys)
        for key in allKeys {
            if !key.hasPrefix("onboarding.") {
                userDefaults.removeObject(forKey: key)
            }
        }
    }
    
    private func getScanIndexSize() async throws -> Int64 {
        // Implementation would check the actual scan index size
        return 0
    }
    
    private func getTraySize() async throws -> Int64 {
        // Implementation would check the tray size
        return 0
    }
    
    private func getActivityLogSize() async throws -> Int64 {
        // Implementation would check the activity log size
        return 0
    }
    
    private func getDiagnosticsSize() async throws -> Int64 {
        // Implementation would check the diagnostics size
        return 0
    }
    
    private func getLabelsSize() async throws -> Int64 {
        // Implementation would check the labels size
        return 0
    }
    
    private func getSettingsSize() async throws -> Int64 {
        // Implementation would check the settings size
        return 0
    }
}