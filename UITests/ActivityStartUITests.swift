import XCTest

@MainActor
final class ActivityStartUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testOverviewDoesNotScanAndRangePickerContainsOnlyBoundedChoices() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingFakeLibrary", "-skipOnboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["activity.scan.0"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["scan.banner.pause"].exists)
        let probe = app.descendants(matching: .any)["debug.probe"].value as? String ?? ""
        XCTAssertTrue(probe.contains("deleteCalls=0"))
        XCTAssertTrue(probe.contains("tray=0"))
        let change = app.buttons["scan.changeScope"]
        for _ in 0..<6 { if change.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(change.exists)
        change.tap()
        XCTAssertTrue(app.navigationBars["Start a small scan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Past month"].exists)
        XCTAssertTrue(app.staticTexts["Past two months"].exists)
        XCTAssertFalse(app.staticTexts["Full library"].exists)
        XCTAssertFalse(app.staticTexts["Select album"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["scan.banner.pause"].exists)
    }
}
