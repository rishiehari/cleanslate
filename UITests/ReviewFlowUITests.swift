import XCTest

/// End-to-end Review -> Approve -> Tray -> Delete flow on the deterministic fake library.
final class ReviewFlowUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(keepTray: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingFakeLibrary", "-skipOnboarding"] + (keepTray ? ["-keepTray"] : [])
        app.launch()
        XCTAssertTrue(app.buttons["category.exact"].waitForExistence(timeout: 8))
        return app
    }

    private func backToHome(_ app: XCUIApplication) {
        while !app.buttons["tray.button"].exists, app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
        }
    }

    private func probe(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any)["debug.probe"].value as? String ?? ""
    }

    private func openGroup(_ app: XCUIApplication, category: String, id: String) {
        app.buttons["category.\(category)"].tap()
        let row = app.buttons["group.\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "missing group row \(id)")
        row.tap()
        XCTAssertTrue(app.buttons["approval.approve"].waitForExistence(timeout: 5))
    }

    func testExactGroupOpensPreMarkedAndOneTapApproveMovesToTrayWithoutDeleting() {
        let app = launch()
        openGroup(app, category: "exact", id: "test-ex1-keep")
        XCTAssertTrue(app.buttons["tile.ex1-copy"].label.hasPrefix("Delete"), app.buttons["tile.ex1-copy"].label)
        XCTAssertTrue(app.buttons["approval.approve"].isEnabled)
        app.buttons["approval.approve"].tap()
        XCTAssertTrue(app.buttons["toast.undo"].waitForExistence(timeout: 3))
        let state = probe(app)
        XCTAssertTrue(state.contains("deleteCalls=0"), state)
        XCTAssertTrue(state.contains("tray=1"), state)
    }

    func testApproveOpensTheNextGroupInsteadOfGoingBack() {
        let app = launch()
        openGroup(app, category: "exact", id: "test-ex1-keep")
        XCTAssertTrue(app.navigationBars["1 of 4"].exists)
        app.buttons["approval.approve"].tap()
        XCTAssertTrue(app.navigationBars["2 of 4"].waitForExistence(timeout: 3), "the next group should open")
        app.buttons["approval.skip"].tap()
        XCTAssertTrue(app.navigationBars["3 of 4"].waitForExistence(timeout: 3))
        XCTAssertTrue(probe(app).contains("tray=1"), probe(app))
    }

    func testSimilarGroupOpensWithNothingMarkedDeleteAndCannotApproveUntilUserPicks() {
        let app = launch()
        openGroup(app, category: "similar", id: "test-sim1-a")
        XCTAssertTrue(app.buttons["tile.sim1-b"].label.hasPrefix("Not decided"), app.buttons["tile.sim1-b"].label)
        XCTAssertFalse(app.buttons["approval.approve"].isEnabled)
        app.buttons["tile.sim1-b"].tap()
        XCTAssertTrue(app.buttons["tile.sim1-b"].label.hasPrefix("Delete"))
        XCTAssertTrue(app.buttons["approval.approve"].isEnabled)
    }

    func testCannotRemoveTheLastKeep() {
        let app = launch()
        openGroup(app, category: "exact", id: "test-ex1-keep")
        app.buttons["tile.ex1-keep"].tap()
        XCTAssertTrue(app.staticTexts["Keep at least one photo in each group."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["tile.ex1-keep"].label.hasPrefix("Keep"))
    }

    func testProtectedPhotoShowsReasonAndDoesNotToggle() {
        let app = launch()
        openGroup(app, category: "exact", id: "test-fav-keep")
        XCTAssertTrue(app.buttons["tile.fav-copy"].label.contains("Favorite"), app.buttons["tile.fav-copy"].label)
        app.buttons["tile.fav-copy"].tap()
        XCTAssertTrue(app.staticTexts["Favorite — always kept"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["approval.approve"].isEnabled)
    }

    func testUndoRevertsApproval() {
        let app = launch()
        openGroup(app, category: "exact", id: "test-ex1-keep")
        app.buttons["approval.approve"].tap()
        XCTAssertTrue(app.buttons["toast.undo"].waitForExistence(timeout: 3))
        app.buttons["toast.undo"].tap()
        XCTAssertTrue(probe(app).contains("tray=0"), probe(app))
    }

    func testApproveAllThenTrayDeleteRemovesCopiesAndKeepsKeepers() {
        let app = launch()
        app.buttons["category.exact"].tap()
        XCTAssertTrue(app.buttons["inbox.approveall"].waitForExistence(timeout: 5))
        app.buttons["inbox.approveall"].tap()
        app.buttons["approveall.confirm"].tap()
        backToHome(app)
        XCTAssertTrue(probe(app).contains("tray=3"), probe(app))
        XCTAssertTrue(probe(app).contains("deleteCalls=0"), "approving must never delete")
        app.buttons["tray.button"].tap()
        app.buttons["tray.delete"].tap()
        XCTAssertTrue(app.buttons["confirm.continue"].waitForExistence(timeout: 3))
        app.buttons["confirm.continue"].tap()
        XCTAssertTrue(app.otherElements["receipt.screen"].waitForExistence(timeout: 8)
                      || app.buttons["receipt.done"].waitForExistence(timeout: 8))
        app.buttons["receipt.done"].tap()
        let state = probe(app)
        XCTAssertTrue(state.contains("assets=22"), "25 assets minus 3 copies: \(state)")   // keepers + similar + favorite pair survive
        XCTAssertTrue(state.contains("tray=0"), state)
    }

    func testCancelInConfirmSheetDeletesNothing() {
        let app = launch()
        openGroup(app, category: "exact", id: "test-ex1-keep")
        app.buttons["approval.approve"].tap()
        backToHome(app)
        app.buttons["tray.button"].tap()
        app.buttons["tray.delete"].tap()
        XCTAssertTrue(app.buttons["confirm.cancel"].waitForExistence(timeout: 3))
        app.buttons["confirm.cancel"].tap()
        XCTAssertTrue(app.buttons["tray.delete"].waitForExistence(timeout: 3))
        app.buttons["Close"].tap()
        let state = probe(app)
        XCTAssertTrue(state.contains("deleteCalls=0") && state.contains("assets=25") && state.contains("tray=1"), state)
    }

    func testTrayPersistsAcrossRelaunch() {
        var app = launch()
        openGroup(app, category: "exact", id: "test-ex2-keep")
        app.buttons["approval.approve"].tap()
        backToHome(app)
        XCTAssertTrue(probe(app).contains("tray=1"))
        app.terminate()
        app = launch(keepTray: true)
        XCTAssertTrue(probe(app).contains("tray=1"), probe(app))
    }

    func testAccessibilityAuditOnHomeAndReview() throws {
        let app = launch()
        try audit(app)
        openGroup(app, category: "exact", id: "test-ex1-keep")
        try audit(app)
    }

    /// Full audit. One documented exemption: the contrast sampler cannot measure the two Liquid Glass
    /// controls of the approval bar (adaptive material). Their legibility was verified on screenshots
    /// (docs/screens/step2b-v2) and by using solid-fade backing + system label colors. Every other
    /// element, and every other audit type, stays enforced.
    private func audit(_ app: XCUIApplication) throws {
        let glassControls: Set<String> = ["approval.skip", "approval.approve"]
        try app.performAccessibilityAudit(for: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .trait]) { issue in
            issue.auditType == .contrast && glassControls.contains(issue.element?.identifier ?? "")
        }
    }

    // MARK: Step 7 — similar shots

    func testWarnedPhotoAsksBeforeItCanBeMarkedAndCanBeAcknowledged() {
        let app = launch()
        openGroup(app, category: "similar", id: "test-sim1-a")
        XCTAssertTrue(app.buttons["chip.differentPeople"].waitForExistence(timeout: 5), "the extra person is flagged")
        app.buttons["tile.sim1-b"].tap()
        XCTAssertTrue(app.buttons["warning.confirm"].waitForExistence(timeout: 3), "tapping a warned photo asks first")
        XCTAssertTrue(app.buttons["tile.sim1-b"].label.hasPrefix("Not decided"))
        app.buttons["warning.cancel"].tap()
        XCTAssertFalse(app.buttons["approval.approve"].isEnabled, "nothing is marked yet")
        app.buttons["tile.sim1-b"].tap()
        app.buttons["warning.confirm"].tap()
        XCTAssertTrue(app.buttons["tile.sim1-b"].label.hasPrefix("Delete"))
        XCTAssertTrue(app.buttons["approval.approve"].isEnabled)
    }

    func testMarkTheRestLeavesWarnedPhotosAloneAndUndoRestores() {
        let app = launch()
        openGroup(app, category: "similar", id: "test-sim1-a")
        XCTAssertTrue(app.buttons["chip.differentPeople"].waitForExistence(timeout: 5))
        app.buttons["review.markrest"].tap()
        XCTAssertTrue(app.buttons["tile.sim1-c"].label.hasPrefix("Delete"))
        XCTAssertTrue(app.buttons["tile.sim1-b"].label.hasPrefix("Not decided"), "the photo with an extra person still needs a look")
        XCTAssertTrue(probe(app).contains("deleteCalls=0"))
        app.buttons["review.undo"].tap()
        XCTAssertTrue(app.buttons["tile.sim1-c"].label.hasPrefix("Not decided"))
    }
}
