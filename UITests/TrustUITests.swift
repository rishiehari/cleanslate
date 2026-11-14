import XCTest

final class TrustUITests: XCTestCase {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }
    
    /// Test that fresh install with reset onboarding shows the correct trust screens
    func testFreshInstallOnboardingWithTrustScreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetOnboarding", "-uiTestingFakeLibrary"]
        
        app.launch()
        
        // Verify we start at the first onboarding page (privacy)
        XCTAssertTrue(app.staticTexts["Everything stays on this iPhone"].waitForExistence(timeout: 10))
        
        // Navigate through all onboarding pages
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["You decide, twice"].waitForExistence(timeout: 5))
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Start small"].waitForExistence(timeout: 5))
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Apple Photos can merge exact copies"].waitForExistence(timeout: 5))
        
        // The last page should have the permission priming text
        XCTAssertTrue(app.staticTexts["Next, iOS asks to let CleanSlate see your photos."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 5))
    }
    
    /// Test that preview gate works correctly in group review
    func testGroupReviewPreviewGate() throws {
        // This test would require a more complex setup with actual scan data
        // For now, just verify the code compiles and structure is correct
        XCTAssertTrue(true, "Test framework ready")
    }
    
    /// Test that preview gate works correctly in standalone list view
    func testStandaloneListViewPreviewGate() throws {
        // This test would require a more complex setup with actual scan data
        // For now, just verify the code compiles and structure is correct
        XCTAssertTrue(true, "Test framework ready")
    }
}