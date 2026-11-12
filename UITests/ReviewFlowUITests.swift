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

    /// The photo grid is lazy and tiles are large, so a lower tile may not exist in the accessibility tree until it
    /// is scrolled near the screen. Scrolling only brings it into view; it never changes any decision.
    private func scrollToTile(_ app: XCUIApplication, _ id: String) {
        let tile = app.buttons["tile.\(id)"]
        var attempts = 0
        while !tile.exists && attempts < 6 { app.swipeUp(); attempts += 1 }
        XCTAssertTrue(tile.waitForExistence(timeout: 3), "tile \(id) never appeared")
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
        // sim1-b shows an extra person, so tapping it asks first (testWarnedPhotoAsksBeforeItCanBeMarked...).
        // The user's pick here is the unwarned sim1-c.
        scrollToTile(app, "sim1-c")
        app.buttons["tile.sim1-c"].tap()
        XCTAssertTrue(app.buttons["tile.sim1-c"].label.hasPrefix("Delete"), app.buttons["tile.sim1-c"].label)
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
    ///
    ///
    /// Second, geometry-bound exemption (2026-11-12): scroll content that is physically overlapped by system
    /// chrome at the current scroll offset is sampled against adaptive material or the iOS 26 scroll-edge fade.
    /// Chrome zones are (a) the floating tab bar plus the 44 pt fade band above it and (b) the status/navigation
    /// area plus the 44 pt fade band below it. A contrast issue is waived ONLY while the element intersects a
    /// zone; every waived element is then scrolled fully on screen and clear of all zones and re-audited with no
    /// exemption, so its real contrast is still enforced.
    private func audit(_ app: XCUIApplication) throws {
        let glassControls: Set<String> = ["approval.skip", "approval.approve"]
        let zones = chromeZones(app)
        let inChrome: @Sendable (CGRect) -> Bool = { frame in zones.contains { $0.intersects(frame) } }
        let waived = WaivedElements()
        try app.performAccessibilityAudit(for: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .trait]) { issue in
            guard issue.auditType == .contrast, let element = issue.element else { return false }
            if glassControls.contains(element.identifier) { return true }
            if inChrome(element.frame) { waived.append(element.identifier, element.label); return true }
            return false
        }
        let occluded = waived.items
        print("AUDIT_CHROME_WAIVED count=\(occluded.count) \(occluded.map { $0.id.isEmpty ? $0.label : $0.id })")
        guard !occluded.isEmpty else { return }
        let window = app.windows.firstMatch.frame
        for (id, label) in occluded {
            // Resolve the flagged element unambiguously: a duplicate label/identifier could otherwise make the
            // clear-of-chrome check (and the re-audit) look at a different element than the one waived.
            let query = id.isEmpty ? app.staticTexts.matching(NSPredicate(format: "label == %@", label))
                                   : app.descendants(matching: .any).matching(identifier: id)
            XCTAssertEqual(query.count, 1, "Waived element '\(id.isEmpty ? label : id)' is not unique; cannot re-audit it reliably")
            guard query.count == 1 else { continue }
            let element = query.element(boundBy: 0)
            for _ in 0..<6 where element.exists && inChrome(element.frame) {
                if let bottom = zones.last, element.frame.intersects(bottom) { app.swipeUp() } else { app.swipeDown() }
            }
            let clear = element.exists && !inChrome(element.frame) && window.contains(element.frame)
            XCTAssertTrue(clear, "Waived element '\(id.isEmpty ? label : id)' could not be moved clear of system chrome for re-audit")
            guard clear else { continue }
            try app.performAccessibilityAudit(for: [.contrast]) { issue in
                guard let other = issue.element, !(other.identifier == id && other.label == label) else { return false }
                return glassControls.contains(other.identifier) || inChrome(other.frame)
            }
        }
        for _ in 0..<6 { app.swipeDown() }
    }

    /// [top zone, bottom zone] in screen points; see `audit`.
    private func chromeZones(_ app: XCUIApplication) -> [CGRect] {
        let fadeBand: CGFloat = 44
        let window = app.windows.firstMatch.frame
        let nav = app.navigationBars.firstMatch
        let topEdge = max(nav.exists ? nav.frame.maxY : 0, app.statusBars.firstMatch.exists ? app.statusBars.firstMatch.frame.maxY : 62)
        let top = CGRect(x: window.minX, y: window.minY, width: window.width, height: topEdge + fadeBand)
        let bar = app.tabBars.firstMatch
        let barTop = bar.exists ? bar.frame.minY : window.maxY - 83
        let bottom = CGRect(x: window.minX, y: barTop - fadeBand, width: window.width, height: window.maxY - barTop + fadeBand)
        return [top, bottom]
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
        scrollToTile(app, "sim1-c")
        XCTAssertTrue(app.buttons["tile.sim1-c"].label.hasPrefix("Delete"))
        XCTAssertTrue(app.buttons["tile.sim1-b"].label.hasPrefix("Not decided"), "the photo with an extra person still needs a look")
        XCTAssertTrue(probe(app).contains("deleteCalls=0"))
        app.buttons["review.undo"].tap()
        XCTAssertTrue(app.buttons["tile.sim1-c"].label.hasPrefix("Not decided"))
    }
}

/// Thread-safe collector for audit issues waived while overlapped by the tab bar (audit handlers are @Sendable).
private final class WaivedElements: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(id: String, label: String)] = []
    func append(_ id: String, _ label: String) { lock.lock(); storage.append((id, label)); lock.unlock() }
    var items: [(id: String, label: String)] { lock.lock(); defer { lock.unlock() }; return storage }
}
