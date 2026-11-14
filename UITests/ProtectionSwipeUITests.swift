import XCTest

/// N05 C8: "Never suggest" from Swipe n Save (fake library, two orientations of one pair).
final class ProtectionSwipeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingFakeLibrary", "-uiTestingSwipe", "-skipOnboarding", "-uiTestingProtectionStore"] + extra
        app.launch()
        app.tabBars.buttons["Swipe n Save"].tap()
        XCTAssertTrue(app.buttons["swipe.left"].waitForExistence(timeout: 8))
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    private func probe(_ app: XCUIApplication) -> String { element(app, "debug.probe").value as? String ?? "" }

    func testSwipeNeverSuggestBlocksOnlyTheOrientationThatWouldDeleteTheProtectedPhoto() {
        let app = launch()
        let protect = app.buttons["swipe.protect"]
        XCTAssertTrue(protect.waitForExistence(timeout: 3))
        protect.tap()
        XCTAssertTrue(element(app, "protect.sheet").waitForExistence(timeout: 5))
        let toggle = app.switches["protect.photo.sw1-left"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        app.buttons["protect.confirm"].tap()
        XCTAssertTrue(app.buttons["toast.undo"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["swipe.left"].waitForExistence(timeout: 5), "the pair is still offered: one orientation is allowed")
        // Keeping the RIGHT photo would delete the protected LEFT one: blocked with the rule's own words.
        app.buttons["swipe.right"].tap()
        XCTAssertTrue(app.staticTexts["Protected by your rule — always kept"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["swipe.approve"].isEnabled)
        // Keeping the protected LEFT photo and deleting the right one is fine.
        app.buttons["swipe.left"].tap()
        XCTAssertTrue(app.buttons["swipe.approve"].isEnabled)
        app.buttons["swipe.approve"].tap()
        XCTAssertTrue(probe(app).contains("tray=1"), probe(app))
        XCTAssertTrue(probe(app).contains("deleteCalls=0"), probe(app))
    }

    func testSwipeEntryIsHiddenWhenTheFeatureIsOff() {
        let app = launch(["-disableProtectionRulesUI"])
        XCTAssertTrue(app.buttons["swipe.compare"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["swipe.protect"].exists)
    }
}
