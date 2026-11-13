import XCTest

@MainActor
final class ProtectionDemoUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingFakeLibrary", "-uiTestingAuth", "notDetermined", "-resetOnboarding"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 8))
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func openDemo(_ app: XCUIApplication) {
        let entry = app.buttons["onboarding.protectionDemo"]
        reveal(entry, in: app)
        entry.tap()
        XCTAssertTrue(app.navigationBars["Protection example"].waitForExistence(timeout: 5))
    }

    func testSampleProtectResetAndReopenLeavePhotosAndTrayUntouched() {
        let app = launch()
        openDemo(app)
        XCTAssertTrue(app.staticTexts["1 sample deletion suggestion"].exists)
        let protect = app.buttons["protectionDemo.protect"]
        reveal(protect, in: app)
        protect.tap()
        XCTAssertTrue(app.staticTexts["Kept safe by your rule"].exists)
        XCTAssertTrue(app.staticTexts["No sample deletion suggestion"].exists)
        app.buttons["protectionDemo.reset"].tap()
        XCTAssertTrue(app.staticTexts["1 sample deletion suggestion"].exists)
        app.buttons["protectionDemo.protect"].tap()
        app.buttons["protectionDemo.done"].tap()
        openDemo(app)
        XCTAssertTrue(app.staticTexts["1 sample deletion suggestion"].exists, "each presentation starts with a fresh sample")
        app.buttons["protectionDemo.done"].tap()
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.done"].tap()
        XCTAssertTrue(app.buttons["permission.allow"].waitForExistence(timeout: 5))
        let probe = app.descendants(matching: .any)["debug.probe"].value as? String ?? ""
        XCTAssertTrue(probe.contains("deleteCalls=0"), probe)
        XCTAssertTrue(probe.contains("tray=0"), probe)
    }

    func testDemoCanBeProtectedAndDismissedAtAX5() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openDemo(app)
        let protect = app.buttons["protectionDemo.protect"]
        reveal(protect, in: app)
        protect.tap()
        XCTAssertTrue(app.staticTexts["No sample deletion suggestion"].exists)
        app.buttons["protectionDemo.done"].tap()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 5))
    }

    func testFlagOffKeepsOriginalThreePageOnboardingWithoutDemo() {
        let app = launch(["-disableProtectionRulesUI"])
        XCTAssertFalse(app.buttons["onboarding.protectionDemo"].exists)
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.done"].tap()
        XCTAssertTrue(app.buttons["permission.allow"].waitForExistence(timeout: 5))
    }
}
