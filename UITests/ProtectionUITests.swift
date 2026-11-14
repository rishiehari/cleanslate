import XCTest
import UIKit

private final class ProtectionAuditFindings: @unchecked Sendable { var lines: [String] = [] }

/// N05 C7: "Never suggest" on iPhone. Everything runs on the deterministic fake library (no real photos).
/// Launch switches: `-uiTestingProtectionStore` (rules persist in a temporary database), `-uiTestingProtectedAssets a,b`
/// (rules for these assets exist at launch), `-uiTestingProtectionUnavailable` (the rule store cannot be read),
/// `-disableProtectionRulesUI` (hides the entry points, enforcement stays).
final class ProtectionUITests: XCTestCase {
    private let ax3 = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]

    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingFakeLibrary", "-skipOnboarding"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["category.exact"].waitForExistence(timeout: 8))
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    private func probe(_ app: XCUIApplication) -> String { element(app, "debug.probe").value as? String ?? "" }

    private func openGroup(_ app: XCUIApplication, id: String) {
        app.buttons["category.exact"].tap()
        let row = app.buttons["group.\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 8), "missing group row \(id)")
        row.tap()
        XCTAssertTrue(app.buttons["approval.approve"].waitForExistence(timeout: 5))
    }

    private func backToHome(_ app: XCUIApplication) {
        var guardCount = 0
        while !app.buttons["tray.button"].exists, app.navigationBars.buttons.firstMatch.exists, guardCount < 6 {
            app.navigationBars.buttons.firstMatch.tap(); guardCount += 1
        }
        XCTAssertTrue(app.buttons["tray.button"].waitForExistence(timeout: 5))
    }

    private func openRules(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["dashboard.menu"].waitForExistence(timeout: 5))
        app.buttons["dashboard.menu"].tap()
        let entry = app.buttons["menu.protection"]
        XCTAssertTrue(entry.waitForExistence(timeout: 3), "the rules screen should be reachable from the Settings menu")
        entry.tap()
        XCTAssertTrue(element(app, "protection.screen").waitForExistence(timeout: 5))
    }

    /// The photo rows are toggles: tap the switch itself (a row tap does not flip it).
    private func choosePhoto(_ app: XCUIApplication, _ id: String) {
        let toggle = app.switches["protect.photo.\(id)"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "missing toggle for \(id)")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()      // the switch sits at the trailing edge
        XCTAssertEqual(toggle.value as? String, "1", "the photo should now be chosen")
    }

    private func openProtectSheetFromMenu(_ app: XCUIApplication) {
        app.buttons["More"].tap()
        let entry = app.buttons["review.protect"]
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        entry.tap()
        XCTAssertTrue(element(app, "protect.sheet").waitForExistence(timeout: 5))
    }

    // MARK: Protect from a review

    func testProtectSheetFromTheMenuProtectsTheCopyAndNothingIsDeleted() {
        let app = launch(["-uiTestingProtectionStore"])
        openGroup(app, id: "test-ex1-keep")
        openProtectSheetFromMenu(app)
        XCTAssertFalse(app.buttons["protect.confirm"].isEnabled, "nothing chosen yet")
        choosePhoto(app, "ex1-copy")
        XCTAssertTrue(app.buttons["protect.confirm"].isEnabled)
        app.buttons["protect.confirm"].tap()
        XCTAssertTrue(element(app, "review.protected").waitForExistence(timeout: 8), "the group is now kept safe by the rule")
        XCTAssertTrue(app.staticTexts["Kept safe by your rule. Nothing was deleted."].exists)
        XCTAssertTrue(app.buttons["toast.undo"].waitForExistence(timeout: 3), "the toast offers Undo for the rule")
        XCTAssertTrue(probe(app).contains("deleteCalls=0"), probe(app))
    }

    func testCancelClosesTheSheetWithoutCreatingARule() {
        let app = launch(["-uiTestingProtectionStore"])
        openGroup(app, id: "test-ex1-keep")
        openProtectSheetFromMenu(app)
        choosePhoto(app, "ex1-copy")
        app.buttons["protect.cancel"].tap()
        XCTAssertTrue(app.buttons["approval.approve"].waitForExistence(timeout: 3))
        XCTAssertFalse(element(app, "protect.sheet").exists)
        XCTAssertTrue(app.buttons["tile.ex1-copy"].label.hasPrefix("Delete"), "the group is untouched")
    }

    func testUndoInTheToastRemovesTheRule() {
        let app = launch(["-uiTestingProtectionStore"])
        openGroup(app, id: "test-ex1-keep")
        openProtectSheetFromMenu(app)
        choosePhoto(app, "ex1-copy")
        app.buttons["protect.confirm"].tap()
        XCTAssertTrue(app.buttons["toast.undo"].waitForExistence(timeout: 8))
        app.buttons["toast.undo"].tap()
        backToHome(app)
        openRules(app)
        XCTAssertTrue(element(app, "protection.empty").waitForExistence(timeout: 5), "Undo took the rule away")
        XCTAssertTrue(probe(app).contains("deleteCalls=0"))
    }

    // MARK: Rules screen (G4 UI)

    func testRulesScreenListsRulesAndRemovalNeedsConfirmation() {
        let app = launch(["-uiTestingProtectedAssets", "ex1-copy"])
        openRules(app)
        let remove = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'protection.rule.' AND identifier ENDSWITH '.remove'")).firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "protection.section.photos").exists)
        remove.tap()
        XCTAssertTrue(app.staticTexts["It may be suggested again after your next scan. Nothing is deleted."].waitForExistence(timeout: 3))
        app.buttons["Remove rule"].firstMatch.tap()
        XCTAssertTrue(element(app, "protection.empty").waitForExistence(timeout: 5))
    }

    func testRemovingARuleDoesNotRestoreTheTrayEntry() {
        let app = launch(["-uiTestingProtectionStore"])
        openGroup(app, id: "test-ex2-keep")
        app.buttons["approval.approve"].tap()
        backToHome(app)
        XCTAssertTrue(probe(app).contains("tray=1"), probe(app))
        // Reopen the reviewed group and protect its copy from the tile menu (G1 UI).
        app.buttons["category.exact"].tap()
        let reviewed = element(app, "inbox.reviewed").firstMatch
        XCTAssertTrue(reviewed.waitForExistence(timeout: 5))
        reviewed.tap()
        app.buttons["group.test-ex2-keep"].tap()
        let tile = app.buttons["tile.ex2-copy"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        tile.press(forDuration: 1.2)
        let neverSuggest = app.buttons["protect.action.ex2-copy"]
        XCTAssertTrue(neverSuggest.waitForExistence(timeout: 3))
        neverSuggest.tap()
        XCTAssertTrue(element(app, "protect.sheet").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["protect.confirm"].isEnabled, "the long-pressed photo is already chosen")
        app.buttons["protect.confirm"].tap()
        XCTAssertTrue(app.buttons["toast.undo"].waitForExistence(timeout: 8))
        backToHome(app)
        XCTAssertTrue(probe(app).contains("tray=0"), "the protected entry no longer counts as ready: \(probe(app))")
        XCTAssertTrue(probe(app).contains("deleteCalls=0"))
        app.buttons["tray.button"].tap()
        XCTAssertTrue(element(app, "tray.attention").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Protected by your rule — always kept"].exists)
        app.buttons["Close"].tap()
        // Now remove the rule: the entry must still need a fresh review.
        openRules(app)
        let remove = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'protection.rule.' AND identifier ENDSWITH '.remove'")).firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        app.buttons["Remove rule"].firstMatch.tap()
        XCTAssertTrue(element(app, "protection.empty").waitForExistence(timeout: 5))
        backToHome(app)
        XCTAssertTrue(probe(app).contains("tray=0"), "removing the rule must not make the entry deletable again: \(probe(app))")
        app.buttons["tray.button"].tap()
        XCTAssertTrue(element(app, "tray.attention").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tray.delete"].exists)
    }

    // MARK: Launch-time rules

    func testRulesAtLaunchKeepTheirGroupsOutOfTheInbox() {
        let app = launch(["-uiTestingProtectedAssets", "ex1-copy,ex2-copy"])
        app.buttons["category.exact"].tap()
        XCTAssertTrue(app.buttons["group.test-ex3-keep"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["group.test-ex1-keep"].exists)
        XCTAssertFalse(app.buttons["group.test-ex2-keep"].exists)
    }

    // MARK: States (E17 UI)

    func testLimitedAccessShowsTheBannerAndAnUnreachablePhotoIsMarkedUnavailable() {
        let app = launch(["-uiTestingAuth", "limited", "-uiTestingProtectedAssets", "photo-you-no-longer-share"])
        openRules(app)
        XCTAssertTrue(element(app, "protection.limitedBanner").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Protected photos you haven't shared still stay protected."].exists)
        XCTAssertTrue(app.staticTexts["Not available right now"].exists)
    }

    func testUnavailableRulesBlockDeletingFromTheTray() {
        var app = launch()
        openGroup(app, id: "test-ex1-keep")
        app.buttons["approval.approve"].tap()
        backToHome(app)
        app.terminate()
        app = launch(["-keepTray", "-uiTestingProtectionUnavailable"])
        app.buttons["tray.button"].tap()
        XCTAssertTrue(element(app, "tray.protectionBlocked").waitForExistence(timeout: 5))
        let delete = app.buttons["tray.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        XCTAssertFalse(delete.isEnabled, "nothing can be deleted while the rules can't be checked")
        app.buttons["tray.protectionFix"].tap()
        let found = element(app, "protection.unavailable").waitForExistence(timeout: 5)
        let ids = app.descendants(matching: .any).allElementsBoundByIndex.map { "\($0.identifier)|\($0.label)" }.filter { $0 != "|" }
        XCTAssertTrue(found, "visible: \(ids)")
        XCTAssertTrue(app.buttons["protection.retry"].exists)
        XCTAssertTrue(probe(app).contains("deleteCalls=0"))
    }

    // MARK: Flag (E23 UI)

    func testFlagOffHidesTheEntryPointsButStillEnforcesAndKeepsTheRulesScreen() {
        let app = launch(["-disableProtectionRulesUI", "-uiTestingProtectedAssets", "ex1-copy"])
        app.buttons["category.exact"].tap()
        XCTAssertTrue(app.buttons["group.test-ex2-keep"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["group.test-ex1-keep"].exists, "enforcement is not behind the flag")
        app.buttons["group.test-ex2-keep"].tap()
        XCTAssertTrue(app.buttons["approval.approve"].waitForExistence(timeout: 5))
        app.buttons["More"].tap()
        XCTAssertTrue(app.buttons["review.wrong"].waitForExistence(timeout: 3), "the menu is open")
        XCTAssertFalse(app.buttons["review.protect"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.15)).tap()      // dismiss the menu
        backToHome(app)
        openRules(app)                       // rules exist, so the screen stays reachable
    }

    func testFlagOffWithNoRulesHidesTheMenuEntry() {
        let app = launch(["-disableProtectionRulesUI"])
        app.buttons["dashboard.menu"].tap()
        XCTAssertTrue(app.buttons["menu.diagnostics"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["menu.protection"].exists)
    }

    func testDateRangeCanBeChosenAndSavedWithoutDeletingPhotos() {
        let app = launch(["-uiTestingProtectionStore"])
        openGroup(app, id: "test-ex1-keep")
        openProtectSheetFromMenu(app)
        let scope = element(app, "protect.scope")
        scope.tap()
        let dates = app.buttons["Photos from these dates"]
        XCTAssertTrue(dates.waitForExistence(timeout: 5))
        dates.tap()
        XCTAssertTrue(element(app, "protect.range.start").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "protect.range.end").exists)
        XCTAssertTrue(app.buttons["protect.confirm"].isEnabled)
        app.buttons["protect.confirm"].tap()
        XCTAssertTrue(app.buttons["toast.undo"].waitForExistence(timeout: 5))
        XCTAssertTrue(probe(app).contains("deleteCalls=0"), probe(app))
        XCTAssertTrue(probe(app).contains("tray=0"), probe(app))
    }

    func testLeavingRulesRestoresMainNavigation() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("Phone tab-visibility regression; native iPad sidebar return coverage is pending")
        }
        let app = launch(["-uiTestingProtectedAssets", "ex1-copy"])
        openRules(app)
        backToHome(app)
        let swipeTab = app.buttons["Swipe n Save"]
        XCTAssertTrue(swipeTab.waitForExistence(timeout: 5))
        XCTAssertTrue(swipeTab.isHittable)
        swipeTab.tap()
        XCTAssertTrue(app.navigationBars["Swipe n Save"].waitForExistence(timeout: 5))
    }

    // MARK: Accessibility

    func testRulesScreenAccessibilityAuditAtAX5() throws {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                          "-uiTestingProtectedAssets", "ex1-copy,photo-you-no-longer-share"])
        openRules(app)
        XCTAssertTrue(app.staticTexts["Not available right now"].waitForExistence(timeout: 5))
        try audit(app)
    }

    func testProtectSheetAccessibilityAuditAtAX5() throws {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-uiTestingProtectionStore"])
        openGroup(app, id: "test-ex1-keep")
        openProtectSheetFromMenu(app)
        try audit(app)
    }

    func testRulesScreenAccessibilityAudit() throws {
        let app = launch(["-uiTestingProtectedAssets", "ex1-copy,photo-you-no-longer-share"])
        openRules(app)
        XCTAssertTrue(app.staticTexts["Not available right now"].waitForExistence(timeout: 5))
        try audit(app)
    }

    func testRulesScreenAccessibilityAuditAtAX3() throws {
        let app = launch(ax3 + ["-uiTestingProtectedAssets", "ex1-copy,photo-you-no-longer-share"])
        openRules(app)
        XCTAssertTrue(app.staticTexts["Not available right now"].waitForExistence(timeout: 5))
        try audit(app)
    }

    func testProtectSheetAccessibilityAudit() throws {
        let app = launch(["-uiTestingProtectionStore"])
        openGroup(app, id: "test-ex1-keep")
        openProtectSheetFromMenu(app)
        try audit(app)
    }

    func testProtectSheetAccessibilityAuditAtAX3() throws {
        let app = launch(ax3 + ["-uiTestingProtectionStore"])
        openGroup(app, id: "test-ex1-keep")
        openProtectSheetFromMenu(app)
        try audit(app)
    }

    /// House audit scope (see DiagnosticsUITests): five types, dynamicType excluded app-wide because `.appText` applies
    /// `.tracking(0)`; the one unattributed render-server finding is ignored by exact signature, everything else fails.
    private func audit(_ app: XCUIApplication) throws {
        let findings = ProtectionAuditFindings()
        // The toolbar "Protect" button is a Liquid Glass control whose adaptive material the contrast sampler cannot measure
        // (same documented exemption as the approval bar in ReviewFlowUITests). "Nearly passed" is a sampler warning, not a failure.
        let glassControls: Set<String> = ["protect.confirm", "protect.cancel"]
        try app.performAccessibilityAudit(for: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .trait]) { issue in
            let artifact = issue.auditType == .elementDetection && issue.element == nil
                && issue.compactDescription == "Potentially inaccessible text"
            let glass = issue.auditType == .contrast && glassControls.contains(issue.element?.identifier ?? "")
            let warning = issue.compactDescription.contains("nearly passed")
            if !artifact && !glass && !warning {
                print("PROTECTION_AUDIT type=\(issue.auditType) detail=\(issue.detailedDescription)")
                let element = issue.element
                findings.lines.append("\(issue.compactDescription) [id=\(element?.identifier ?? "-") label=\(element?.label ?? "-") frame=\(element?.frame ?? .zero)]")
            }
            return true
        }
        XCTAssertTrue(findings.lines.isEmpty, "accessibility audit findings: \(findings.lines)")
    }
}
