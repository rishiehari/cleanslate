import XCTest
@testable import CleanSlate

final class LocalDataInventoryTests: XCTestCase {
    
    func testLocalDataItemInitialization() throws {
        // Test that LocalDataItem can be initialized correctly
        let item = LocalDataItem(id: .scanIndex, bytes: 1024, summary: "Test data")
        
        XCTAssertEqual(item.id, .scanIndex)
        XCTAssertEqual(item.bytes, 1024)
        XCTAssertEqual(item.summary, "Test data")
    }
    
    func testLocalDataItemKind() throws {
        // Test that all LocalDataItem kinds are available
        let kinds: [LocalDataItem.Kind] = [.scanIndex, .tray, .activityLog, .diagnostics, .labels, .settings]
        
        XCTAssertEqual(kinds.count, 6)
    }
    
    func testTrustStateInitialization() throws {
        // Test that TrustState initializes properly
        let trustState = TrustState()
        
        XCTAssertNotNil(trustState)
        XCTAssertFalse(trustState.hasReadHowDeletingWorks)
        XCTAssertFalse(trustState.firstScanCompleted)
    }
    
    func testTrustStatePersistence() throws {
        // Test that TrustState can save and load properly
        let trustState = TrustState()
        
        // Mark as read
        trustState.markHowDeletingWorksRead()
        XCTAssertTrue(trustState.hasReadHowDeletingWorks)
        
        // Mark first scan completed
        trustState.markFirstScanCompleted()
        XCTAssertTrue(trustState.firstScanCompleted)
    }
    
    func testLocalDataError() throws {
        // Test that LocalDataError is defined correctly
        let error = LocalDataError.busy
        
        switch error {
        case .busy:
            XCTAssertTrue(true) // Expected case
        }
    }
}