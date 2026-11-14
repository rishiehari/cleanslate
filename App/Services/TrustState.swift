import Foundation
import Combine

@MainActor
final class TrustState: ObservableObject {
    @Published var hasReadHowDeletingWorks = false
    @Published var firstScanCompleted = false
    
    private let readDeletingKey = "trust.readDeleting.v1"
    private let firstScanKey = "trust.firstScan.v1"
    
    init() {
        load()
    }
    
    func load() {
        hasReadHowDeletingWorks = UserDefaults.standard.bool(forKey: readDeletingKey)
        firstScanCompleted = UserDefaults.standard.bool(forKey: firstScanKey)
    }
    
    func save() {
        UserDefaults.standard.set(hasReadHowDeletingWorks, forKey: readDeletingKey)
        UserDefaults.standard.set(firstScanCompleted, forKey: firstScanKey)
    }
    
    func markHowDeletingWorksRead() {
        hasReadHowDeletingWorks = true
        save()
    }
    
    func markFirstScanCompleted() {
        firstScanCompleted = true
        save()
    }
}