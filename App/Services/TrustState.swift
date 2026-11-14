import Foundation

@MainActor final class TrustState: ObservableObject {
    @Published var hasReadHowDeletingWorks = false
    @Published var firstScanCompleted = false
    
    private let readDeletingKey = "trust.readDeleting.v1"
    private let firstScanKey = "trust.firstScan.v1"
    
    init() {
        hasReadHowDeletingWorks = UserDefaults.standard.bool(forKey: readDeletingKey)
        firstScanCompleted = UserDefaults.standard.bool(forKey: firstScanKey)
    }
    
    func setHasReadHowDeletingWorks(_ value: Bool) {
        hasReadHowDeletingWorks = value
        UserDefaults.standard.set(value, forKey: readDeletingKey)
    }
    
    func setFirstScanCompleted(_ value: Bool) {
        firstScanCompleted = value
        UserDefaults.standard.set(value, forKey: firstScanKey)
    }
}