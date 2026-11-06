import XCTest

final class StandaloneUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingFakeLibrary", "-skipOnboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["category.screenshots"].waitForExistence(timeout: 8))
        return app
    }

    private func probe(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any)["debug.probe"].value as? String ?? ""
    }

    private func backToHome(_ app: XCUIApplication) {
        while !app.buttons["tray.button"].exists, app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
        }
    }

    func testScreenshotsOpenWithNothingSelectedAndProtectedOnesLeftOut() {
        let app = launch()
        app.buttons["category.screenshots"].tap()
        XCTAssertTrue(app.buttons["tile.ss1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tile.ss1"].label.hasPrefix("Not selected"), app.buttons["tile.ss1"].label)
        XCTAssertFalse(app.buttons["approval.approve"].isEnabled, "nothing is selected for you")
        XCTAssertFalse(app.buttons["tile.ss-fav"].exists, "favorites are left out")
        XCTAssertTrue(app.buttons["tile.rec1"].exists, "screen recordings are included")
    }

    func testOlderThanThirtyDaysFilterHidesRecentScreenshots() {
        let app = launch()
        app.buttons["category.screenshots"].tap()
        XCTAssertTrue(app.buttons["tile.ss-recent"].waitForExistence(timeout: 5))
        let older = app.descendants(matching: .any)["standalone.older"]
        XCTAssertTrue(older.waitForExistence(timeout: 3))
        older.tap()
        XCTAssertTrue(app.buttons["tile.ss1"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["tile.ss-recent"].exists)
    }

    func testSelectApproveAndDeleteThroughTheTray() {
        let app = launch()
        app.buttons["category.screenshots"].tap()
        app.buttons["tile.ss1"].tap()
        app.buttons["tile.ss2"].tap()
        XCTAssertTrue(app.buttons["tile.ss1"].label.hasPrefix("Selected"))
        app.buttons["approval.approve"].tap()
        XCTAssertTrue(app.buttons["toast.undo"].waitForExistence(timeout: 3))
        var state = probe(app)
        XCTAssertTrue(state.contains("deleteCalls=0") && state.contains("tray=2"), "approving never deletes: \(state)")
        backToHome(app)
        app.buttons["tray.button"].tap()
        app.buttons["tray.delete"].tap()
        app.buttons["confirm.continue"].tap()
        XCTAssertTrue(app.buttons["receipt.done"].waitForExistence(timeout: 8))
        app.buttons["receipt.done"].tap()
        state = probe(app)
        XCTAssertTrue(state.contains("assets=23") && state.contains("tray=0"), "25 assets minus 2 screenshots: \(state)")
    }

    func testLargeFilesAreListedLargestFirstWithSizes() {
        let app = launch()
        app.buttons["category.largeFiles"].tap()
        XCTAssertTrue(app.buttons["item.big1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["item.big2"].exists)
        XCTAssertFalse(app.buttons["item.vex-a"].exists, "identical copies belong to the Videos inbox, where one is always kept")
        XCTAssertFalse(app.buttons["item.vex-b"].exists)
        XCTAssertFalse(app.buttons["standalone.selectall"].exists, "no one-tap select-all for big videos")
        XCTAssertFalse(app.buttons["item.small1"].exists, "small videos aren't large files")
        XCTAssertFalse(app.buttons["item.rec1"].exists, "screen recordings have their own list")
        XCTAssertLessThan(app.buttons["item.big1"].frame.minY, app.buttons["item.big2"].frame.minY, "largest first")
    }

    func testIdenticalVideosAppearInTheVideosInbox() {
        let app = launch()
        app.buttons["category.videos"].tap()
        XCTAssertTrue(app.buttons["group.test-vex-a"].waitForExistence(timeout: 5))
    }
}
