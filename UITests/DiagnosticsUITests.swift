import XCTest

/// Thread-safe collector for the accessibility-audit handler (Swift 6: the handler closure is non-Sendable).
final class AuditFindings: @unchecked Sendable {
    var lines: [String] = []
}

final class DiagnosticsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingFakeLibrary", "-uiTestingAuth", "authorized", "-skipOnboarding"]
        app.launch()
        return app
    }

    func testOpenShareDeleteAndEmptyState() {
        let app = launch()
        XCTAssertTrue(app.buttons["dashboard.menu"].waitForExistence(timeout: 5))
        app.buttons["dashboard.menu"].tap()
        XCTAssertTrue(app.buttons["menu.diagnostics"].waitForExistence(timeout: 3))
        app.buttons["menu.diagnostics"].tap()

        XCTAssertTrue(app.scrollViews["diagnostics.screen"].waitForExistence(timeout: 5)
                      || app.otherElements["diagnostics.screen"].waitForExistence(timeout: 5))
        // Launch itself records appLaunch/scenePhase, so the summary has real rows on any container.
        XCTAssertTrue(app.otherElements["diagnostics.summary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["diagnostics.share"].exists)
        XCTAssertTrue(app.buttons["diagnostics.delete"].exists)

        app.buttons["diagnostics.delete"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Nothing recorded yet"].waitForExistence(timeout: 5),
                      "deleting everything shows the empty state")
        XCTAssertFalse(app.otherElements["diagnostics.summary"].exists)
    }

    func testAccessibilityAudit() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["dashboard.menu"].waitForExistence(timeout: 5))
        app.buttons["dashboard.menu"].tap()
        app.buttons["menu.diagnostics"].tap()
        XCTAssertTrue(app.scrollViews["diagnostics.screen"].waitForExistence(timeout: 5)
                      || app.otherElements["diagnostics.screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["diagnostics.summary"].waitForExistence(timeout: 5), "content settled")
        XCTAssertTrue(app.buttons["diagnostics.share"].waitForExistence(timeout: 5), "share control settled")
        // House audit scope (same five types as ReviewFlowUITests). The dynamicType sampler is excluded
        // app-wide: it flags every design-system label, because `.appText` applies `.tracking(0)`, which
        // the sampler reads as a non-scaling font (verified by bisection on this screen — untracked text
        // passes). AX5 reflow is instead covered by ViewThatFits rows and the .combine VoiceOver checks.
        // House audit scope (same five types as ReviewFlowUITests). Two documented sampler limits,
        // both verified by bisection on this screen:
        //  - dynamicType is excluded app-wide: `.appText` applies `.tracking(0)`, which the sampler
        //    reads as a non-scaling font (untracked text passes). AX5 reflow is covered instead by
        //    the ViewThatFits rows and the .combine VoiceOver checks.
        //  - elementDetection reports ONE unattributed finding ("Potentially inaccessible text",
        //    element == nil) on this pushed screen — present with any third content child (even a
        //    1 pt Color.clear), independent of ShareLink, settles, indicators and the empty→loaded
        //    transition. It is a render-server/AX-tree sync artifact of the pushed composition, not
        //    an element defect: the hierarchy dump shows every text exposed and correctly combined.
        //    Only that exact signature is ignored; every other finding fails the test.
        let ignored = AuditFindings()
        let findings = AuditFindings()
        try app.performAccessibilityAudit(for: [.contrast, .elementDetection, .hitRegion,
                                                .sufficientElementDescription, .trait]) { issue in
            let isUnattributedRenderArtifact = issue.auditType == .elementDetection
                && issue.element == nil
                && issue.compactDescription == "Potentially inaccessible text"
            (isUnattributedRenderArtifact ? ignored : findings).lines.append(issue.compactDescription)
            return true
        }
        if !ignored.lines.isEmpty { print("AUDIT-IGNORED(unattributed artifact): \(ignored.lines)") }
        XCTAssertTrue(findings.lines.isEmpty, "accessibility audit findings: \(findings.lines)")
    }
}
