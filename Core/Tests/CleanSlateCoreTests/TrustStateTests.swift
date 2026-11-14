import XCTest
@testable import CleanSlate

final class TrustStateTests: XCTestCase {
    
    func testInitialValues() throws {
        // Create a new TrustState instance
        let trustState = TrustState()
        
        // Test initial values (should be false)
        XCTAssertFalse(trustState.hasReadHowDeletingWorks)
        XCTAssertFalse(trustState.firstScanCompleted)
    }
    
    func testSetHasReadHowDeletingWorks() throws {
        // Create a new TrustState instance
        let trustState = TrustState()
        
        // Set the value to true
        trustState.setHasReadHowDeletingWorks(true)
        
        // Verify it was set correctly
        XCTAssertTrue(trustState.hasReadHowDeletingWorks)
        
        // Set it back to false
        trustState.setHasReadHowDeletingWorks(false)
        
        // Verify it was set correctly
        XCTAssertFalse(trustState.hasReadHowDeletingWorks)
    }
    
    func testSetFirstScanCompleted() throws {
        // Create a new TrustState instance
        let trustState = TrustState()
        
        // Set the value to true
        trustState.setFirstScanCompleted(true)
        
        // Verify it was set correctly
        XCTAssertTrue(trustState.firstScanCompleted)
        
        // Set it back to false
        trustState.setFirstScanCompleted(false)
        
        // Verify it was set correctly
        XCTAssertFalse(trustState.firstScanCompleted)
    }
}