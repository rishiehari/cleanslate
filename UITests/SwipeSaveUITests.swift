import XCTest

@MainActor
final class SwipeSaveUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingFakeLibrary", "-uiTestingSwipe", "-skipOnboarding"] + extra
        app.launch()
        app.tabBars.buttons["Swipe n Save"].tap()
        XCTAssertTrue(app.buttons["swipe.left"].waitForExistence(timeout: 8))
        return app
    }

    private func value(_ app: XCUIApplication, _ id: String) -> String {
        app.descendants(matching: .any)["swipe.photo.\(id)"].value as? String ?? ""
    }

    private func probe(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any)["debug.probe"].value as? String ?? ""
    }

    func testSwipeLeftKeepsLeftAndExplicitApprovalOnlyAddsRightToSharedTray() {
        let app = launch()
        XCTAssertFalse(app.buttons["swipe.approve"].isEnabled)
        XCTAssertEqual(value(app, "sw1-right"), "Not decided")
        app.otherElements["swipe.pair"].swipeLeft()
        XCTAssertEqual(value(app, "sw1-left"), "Keep")
        XCTAssertEqual(value(app, "sw1-right"), "Delete")
        XCTAssertTrue(probe(app).contains("tray=0"))
        app.buttons["swipe.approve"].tap()
        XCTAssertTrue(app.buttons["toast.undo"].waitForExistence(timeout: 3))
        XCTAssertTrue(probe(app).contains("deleteCalls=0"))
        XCTAssertTrue(probe(app).contains("tray=1"))
        app.tabBars.buttons["Home"].tap()
        app.buttons["tray.button"].tap()
        XCTAssertTrue(app.buttons["tray.delete"].waitForExistence(timeout: 3))
        app.buttons["tray.delete"].tap()
        XCTAssertTrue(app.buttons["confirm.continue"].waitForExistence(timeout: 3))
        app.buttons["confirm.continue"].tap()
        XCTAssertTrue(app.buttons["receipt.done"].waitForExistence(timeout: 8))
        app.buttons["receipt.done"].tap()
        XCTAssertTrue(probe(app).contains("deleteCalls=1"))
    }

    func testSwipeRightKeepsRightAndChoiceUndoRestoresUnmarkedPair() {
        let app = launch()
        app.otherElements["swipe.pair"].swipeRight()
        XCTAssertEqual(value(app, "sw1-right"), "Keep")
        XCTAssertEqual(value(app, "sw1-left"), "Delete")
        app.buttons["swipe.undo"].tap()
        XCTAssertEqual(value(app, "sw1-right"), "Not decided")
        XCTAssertFalse(app.buttons["swipe.approve"].isEnabled)
        XCTAssertTrue(probe(app).contains("tray=0"))
    }

    func testKeepBothAndTrayUndoRestoreOriginalPairWithoutDeleting() {
        let app = launch()
        app.buttons["swipe.left"].tap()
        app.buttons["swipe.both"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["swipe.photo.sw2-left"].waitForExistence(timeout: 3))
        app.buttons["toast.undo"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["swipe.photo.sw1-left"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["swipe.approve"].isEnabled)
        XCTAssertTrue(probe(app).contains("tray=0"))
        XCTAssertTrue(probe(app).contains("deleteCalls=0"))
    }

    func testWarningNeedsAcknowledgementAndCompareIsAvailable() {
        let app = launch()
        app.buttons["swipe.both"].tap()
        app.buttons["swipe.left"].tap()
        XCTAssertTrue(app.buttons["warning.confirm"].waitForExistence(timeout: 4))
        app.buttons["warning.cancel"].tap()
        XCTAssertFalse(app.buttons["swipe.approve"].isEnabled)
        app.buttons["swipe.left"].tap()
        app.buttons["warning.confirm"].tap()
        XCTAssertTrue(app.buttons["swipe.approve"].isEnabled)
        app.buttons["swipe.compare"].tap()
        XCTAssertTrue(app.buttons["compare.done"].waitForExistence(timeout: 3))
        app.buttons["compare.done"].tap()
        XCTAssertTrue(probe(app).contains("deleteCalls=0"))
    }

    func testButtonAlternativesAndTabSwitchPreserveChoice() {
        let app = launch()
        app.buttons["swipe.right"].tap()
        app.tabBars.buttons["Home"].tap()
        app.tabBars.buttons["Swipe n Save"].tap()
        XCTAssertEqual(value(app, "sw1-left"), "Delete")
        XCTAssertTrue(app.buttons["swipe.approve"].isEnabled)
    }

    func testSwipeAccessibilityAudit() throws {
        let app = launch()
        try audit(app)
    }

    func testSwipeAccessibilityAuditAtAX3() throws {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        try audit(app)
    }

    private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit { issue in
            print("Swipe audit: \(issue.compactDescription); \(issue.detailedDescription); element=\(issue.element?.debugDescription ?? "unknown")")
            return false
        }
    }

    func testCaptureSwipeScreens() throws {
        guard let dir = ProcessInfo.processInfo.environment["CAPTURE_DIR"], !dir.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_CAPTURE_DIR to capture screenshots")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (name, extra) in [("light", ["-forceColorScheme", "light"]),
                              ("dark", ["-forceColorScheme", "dark"]),
                              ("ax3", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])] {
            let app = launch(extra: extra)
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/swipe-\(name).png"))
            app.terminate()
        }
    }
}
