import XCTest
import UIKit

/// N05 C9: the protected-photos screen on iPad (list plus inspector, keyboard, narrow fallback).
/// Skipped on iPhone. Fake library only.
@MainActor
final class ProtectionIPadUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    override func tearDown() { XCUIDevice.shared.orientation = .portrait }

    private func launch(_ extra: [String] = []) throws -> XCUIApplication {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad coverage") }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingFakeLibrary", "-skipOnboarding", "-uiTestingProtectedAssets", "ex1-copy,ex2-copy"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["category.exact"].waitForExistence(timeout: 8))
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    private func openRules(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["dashboard.menu"].waitForExistence(timeout: 5))
        app.buttons["dashboard.menu"].tap()
        let entry = app.buttons["menu.protection"]
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        entry.tap()
        XCTAssertTrue(element(app, "protection.screen").waitForExistence(timeout: 5))
    }

    /// Rule rows have a UUID in their identifier; the row itself (not its remove button).
    private func firstRuleRow(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'protection.rule.' AND NOT identifier ENDSWITH '.remove'")).firstMatch
    }

    func testSelectingARuleShowsTheInspectorBesideTheList() throws {
        let app = try launch()
        openRules(app)
        let row = firstRuleRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(element(app, "protection.inspector").waitForExistence(timeout: 5), "a wide window shows the detail in an inspector")
        XCTAssertTrue(firstRuleRow(app).exists, "the list stays visible")
        XCTAssertTrue(element(app, "protection.detail.remove").exists)
        XCTAssertFalse(element(app, "protection.detail").exists)
    }

    func testRotateKeepsTheSelectedRule() throws {
        let app = try launch()
        openRules(app)
        firstRuleRow(app).tap()
        XCTAssertTrue(element(app, "protection.inspector").waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
        let portraitDetail = element(app, "protection.detail")
        let portraitInspector = element(app, "protection.inspector")
        XCTAssertTrue(portraitDetail.waitForExistence(timeout: 5) || portraitInspector.exists,
                      "the selected rule stays open; a narrow detail pushes instead of squeezing the list")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(element(app, "protection.inspector").waitForExistence(timeout: 5))
    }

    func testLargestTextCollapsesTheInspectorIntoAPushedDetail() throws {
        let app = try launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openRules(app)
        let row = firstRuleRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(element(app, "protection.detail").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "protection.inspector").exists)
    }

    func testRemovalFromTheInspectorNeedsConfirmationAndNeverDeletesAPhoto() throws {
        let app = try launch()
        openRules(app)
        firstRuleRow(app).tap()
        let remove = app.buttons["protection.detail.remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(app.staticTexts["It may be suggested again after your next scan. Nothing is deleted."].waitForExistence(timeout: 3))
        app.buttons["Remove rule"].firstMatch.tap()
        XCTAssertFalse(element(app, "protection.inspector").waitForExistence(timeout: 2), "the inspector closes with its rule")
        let probe = element(app, "debug.probe").value as? String ?? ""
        XCTAssertTrue(probe.contains("deleteCalls=0"), probe)
    }

    func testCommandFFocusesSearchAndFiltersByRuleType() throws {
        let app = try launch()
        openRules(app)
        XCTAssertTrue(app.buttons["protection.search"].waitForExistence(timeout: 5))
        app.typeKey("f", modifierFlags: .command)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Command-F opens the search field")
        field.tap()                                                  // make sure it has keyboard focus before typing
        field.typeText("album")
        XCTAssertFalse(firstRuleRow(app).waitForExistence(timeout: 2), "no album rules, so nothing matches")
    }

    func testSearchCanBeClearedAfterNarrowingTheWindow() throws {
        let app = try launch()
        openRules(app)
        app.buttons["protection.search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("album")
        XCTAssertFalse(firstRuleRow(app).exists)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(field.waitForExistence(timeout: 5), "an active filter must remain editable in the compact layout")
        field.buttons["Clear text"].tap()
        XCTAssertTrue(firstRuleRow(app).waitForExistence(timeout: 5))
    }

    func testEscapeCancelsTheSheetWithoutCreatingARule() throws {
        // UNVERIFIED in the simulator: a synthesized Escape key press (XCUIElement.typeKey) does not reach the sheet's
        // `.keyboardShortcut(.cancelAction)` (Command-F does reach its shortcut, see the search test). Needs a real iPad with a hardware
        // keyboard (RELEASE_CHECKLIST: iPad keyboard/pointer, PENDING). The Cancel button is covered by ProtectionUITests.
        try XCTSkipIf(true, "Escape key synthesis is not delivered in the simulator; verify on an iPad with a hardware keyboard")
        let app = try launch()
        openRules(app)
        app.buttons["protection.addRange"].tap()
        XCTAssertTrue(element(app, "protect.sheet").waitForExistence(timeout: 5))
        app.navigationBars["Never suggest"].tap()                      // give the sheet keyboard focus
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertFalse(element(app, "protect.sheet").waitForExistence(timeout: 2), "Escape cancels the sheet")
    }
}
