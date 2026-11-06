import XCTest

final class DashboardUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(onboardingSeen: Bool, auth: String = "authorized") -> XCUIApplication {
        let app = XCUIApplication()
        // "-uiTestingAuth value" is read through UserDefaults' argument domain.
        app.launchArguments = ["-uiTestingFakeLibrary", "-uiTestingAuth", auth,
                               onboardingSeen ? "-skipOnboarding" : "-resetOnboarding"]
        app.launch()
        return app
    }

    func testOnboardingShownThenDashboard() {
        let app = launch(onboardingSeen: false)
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.done"].waitForExistence(timeout: 3))
        app.buttons["onboarding.done"].tap()
        XCTAssertTrue(app.buttons["category.exact"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.done"].waitForNonExistence(timeout: 5))
    }

    func testCategoryCardsRender() {
        let app = launch(onboardingSeen: true)
        XCTAssertTrue(app.buttons["category.exact"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["category.similar"].exists)
        for id in ["videos", "screenshots", "largeFiles"] {
            XCTAssertTrue(app.buttons["category.\(id)"].exists, "category.\(id) should be available now")
        }
    }

    func testOpeningACategoryShowsItsGroups() {
        let app = launch(onboardingSeen: true)
        app.buttons["category.exact"].tap()
        XCTAssertTrue(app.otherElements["inbox.exact"].waitForExistence(timeout: 5)
                      || app.scrollViews["inbox.exact"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'group.'")).firstMatch.exists)
    }

    func testDeniedPermissionShowsSettingsCard() {
        let app = launch(onboardingSeen: true, auth: "denied")
        XCTAssertTrue(app.buttons["permission.allow"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["category.exact"].exists)
    }
}
