import XCTest

final class ScanProgressUITests: XCTestCase {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }
    
    /// Test that scan progress card shows correct information during scanning
    func testScanProgressCardShowsCorrectInformation() throws {
        // Use a fake library with thumbnail delay to simulate real scanning
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingFakeLibrary", "-thumbnailDelay 30"]
        
        app.launch()
        
        // Wait for the onboarding to complete and scan to start
        XCTAssertTrue(app.staticTexts["Reading your 100 most recent photos"].waitForExistence(timeout: 10))
        
        // Check that progress card is visible
        XCTAssertTrue(app.otherElements["scan.progress"].exists)
        
        // Check that count changes during scanning
        let initialCount = app.staticTexts["0 of 0"]
        XCTAssertTrue(initialCount.exists)
        
        // Wait for some progress to be made
        Thread.sleep(forTimeInterval: 2.0)
        
        // Verify the scan is progressing
        XCTAssertFalse(app.staticTexts["0 of 0"].exists)
    }
    
    /// Test that found so far shows correct information
    func testFoundSoFarUpdatesDuringScan() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingFakeLibrary", "-thumbnailDelay 30"]
        
        app.launch()
        
        // Wait for the scan to start
        XCTAssertTrue(app.staticTexts["Reading your 100 most recent photos"].waitForExistence(timeout: 10))
        
        // Wait for some groups to be found
        Thread.sleep(forTimeInterval: 3.0)
        
        // The found text should be updated with actual values
        let foundText = app.staticTexts.matching(identifier: "scan.progress.found").firstMatch
        XCTAssertTrue(foundText.exists)
    }
    
    /// Test that scan can be stopped
    func testScanStop() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingFakeLibrary", "-thumbnailDelay 30"]
        
        app.launch()
        
        // Wait for the scan to start
        XCTAssertTrue(app.staticTexts["Reading your 100 most recent photos"].waitForExistence(timeout: 10))
        
        // Find and tap stop button
        let stopButton = app.buttons["scan.progress.stop"]
        XCTAssertTrue(stopButton.exists)
        
        // Tap stop button
        stopButton.tap()
        
        // Confirm stop
        let confirmStopButton = app.buttons["Stop checking? You keep everything found so far."]
        XCTAssertTrue(confirmStopButton.waitForExistence(timeout: 5))
        confirmStopButton.tap()
        
        // Verify that scan progress card disappears
        XCTAssertFalse(app.otherElements["scan.progress"].exists)
    }
    
    /// Test that scan can be paused
    func testScanPause() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingFakeLibrary", "-thumbnailDelay 30"]
        
        app.launch()
        
        // Wait for the scan to start
        XCTAssertTrue(app.staticTexts["Reading your 100 most recent photos"].waitForExistence(timeout: 10))
        
        // Find and tap pause button
        let pauseButton = app.buttons["scan.progress.pause"]
        XCTAssertTrue(pauseButton.exists)
        pauseButton.tap()
        
        // Verify that scan is paused (pause reason should be visible)
        XCTAssertTrue(app.staticTexts["Paused"].exists)
    }
}