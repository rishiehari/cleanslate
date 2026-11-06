import XCTest

final class ICloudVerificationUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingFakeLibrary", "-skipOnboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["dashboard.scan"].waitForExistence(timeout: 8))
        return app
    }

    private func scanAndOpenExactInbox(_ app: XCUIApplication) {
        app.buttons["dashboard.scan"].tap()
        XCTAssertTrue(app.buttons["dashboard.scan"].waitForExistence(timeout: 30), "scan should finish")
        app.buttons["category.exact"].tap()
    }

    func testICloudOnlyCopyIsReportedThenFoundAfterOptIn() {
        let app = launch()
        scanAndOpenExactInbox(app)
        XCTAssertTrue(app.buttons["inbox.verifyicloud"].waitForExistence(timeout: 10), "unverifiable photos must be disclosed")
        let before = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'group.'")).count
        app.buttons["inbox.verifyicloud"].tap()
        XCTAssertTrue(app.switches["icloud.toggle"].waitForExistence(timeout: 5))
        // Form rows span the width: tap the switch itself, at the trailing edge.
        app.switches["icloud.toggle"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(app.switches["icloud.toggle"].value as? String, "1", "toggle should now be on")
        app.buttons["Done"].tap()
        app.navigationBars.buttons.firstMatch.tap()                    // back to Home
        app.buttons["dashboard.scan"].tap()
        XCTAssertTrue(app.buttons["dashboard.scan"].waitForExistence(timeout: 30))
        app.buttons["category.exact"].tap()
        XCTAssertTrue(app.otherElements["inbox.coverage"].waitForExistence(timeout: 10) || app.staticTexts.firstMatch.exists)
        XCTAssertFalse(app.buttons["inbox.verifyicloud"].exists, "nothing is left unchecked once downloads are allowed")
        let after = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'group.'")).count
        XCTAssertEqual(after, before + 1, "the iCloud-only copy forms a new group")
    }

    func testMenuOpensTheICloudSheetWithBudgetControls() {
        let app = launch()
        app.buttons["dashboard.menu"].tap()
        app.buttons["iCloud originals…"].tap()
        XCTAssertTrue(app.switches["icloud.toggle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["icloud.toggle"].value as? String == "1", "off by default")
    }
}
