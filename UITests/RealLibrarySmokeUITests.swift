import XCTest

/// Opt-in smoke run against the simulator's REAL PhotoKit library (no fake flags).
/// Runs only when `TEST_RUNNER_CLEANSLATE_REALLIB=1` is passed to xcodebuild, and only on a dedicated
/// simulator the owner has loaded with media for local testing. Emits text metrics only
/// (`REALLIB_METRIC key=value`); it never attaches screenshots or prints asset names/metadata.
@MainActor
final class RealLibrarySmokeUITests: XCTestCase {
    #if targetEnvironment(simulator)
    private static let onSimulator = true
    #else
    private static let onSimulator = false
    #endif
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(Self.onSimulator, "Real-library smoke never runs on a physical device.")
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLEANSLATE_REALLIB"] == "1",
                          "Real-library smoke runs only on the dedicated local simulator (CLEANSLATE_REALLIB=1).")
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding"]
        addUIInterruptionMonitor(withDescription: "Photos permission") { alert in
            for label in ["Allow Full Access", "Allow Access to All Photos", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap(); return true
            }
            return false
        }
    }

    private func metric(_ key: String, _ value: Any) { print("REALLIB_METRIC \(key)=\(value)") }

    private func launchToHome() -> Bool {
        let start = Date()
        app.launch()
        let allow = app.buttons["permission.allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap(); app.tap() }
        let ready = app.descendants(matching: .any)["activity.overview"].waitForExistence(timeout: 120)
            || app.buttons["dashboard.scan"].waitForExistence(timeout: 1)
        metric("launch_to_home_s", String(format: "%.1f", Date().timeIntervalSince(start)))
        metric("home_ready", ready)
        return ready
    }

    /// Time for a trivial accessibility query; XCUITest waits for the app's main thread to idle,
    /// so a long value means the main thread was blocked.
    private func probeLatency() -> TimeInterval {
        let t = Date()
        _ = app.tabBars.firstMatch.exists
        return Date().timeIntervalSince(t)
    }

    private func startDefaultScan() -> Bool {
        let scan = app.buttons["dashboard.scan"]
        for _ in 0..<6 where !scan.isHittable { app.swipeUp() }
        guard scan.waitForExistence(timeout: 10) else { metric("scan_button_found", false); return false }
        scan.tap()
        return true
    }

    func test1_FullDefaultScanCompletesResponsively() {
        guard launchToHome() else { XCTFail("Home never became ready"); return }
        metric("overview_suggested_weeks", app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'activity.scan.'")).count)
        guard startDefaultScan() else { XCTFail("No scan button"); return }
        let start = Date()
        let banner = app.descendants(matching: .any)["scan.banner"]
        metric("banner_appeared", banner.waitForExistence(timeout: 30))
        var maxProbe: TimeInterval = 0, probes = 0, slowProbes = 0
        while banner.exists && Date().timeIntervalSince(start) < 1_500 {
            let p = probeLatency(); probes += 1
            maxProbe = max(maxProbe, p); if p > 2 { slowProbes += 1 }
            Thread.sleep(forTimeInterval: 3)
        }
        let elapsed = Date().timeIntervalSince(start)
        metric("scan_elapsed_s", String(format: "%.1f", elapsed))
        metric("scan_finished_before_timeout", !banner.exists)
        metric("probe_count", probes); metric("probe_max_s", String(format: "%.2f", maxProbe)); metric("probe_slow_over_2s", slowProbes)
        metric("pause_reason_visible", app.descendants(matching: .any)["scan.pausereason"].exists)
        metric("groups_visible", app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'group.'")).count)
        metric("categories_visible", app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'category.' OR identifier BEGINSWITH 'inbox.'")).count)
        XCTAssertFalse(banner.exists, "Scan did not finish within 25 minutes")
        XCTAssertLessThan(maxProbe, 5, "Main thread appeared blocked for >5 s during scan")

        // Swipe tab should either offer a pair or an honest empty state.
        let swipeTab = app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Swipe'")).firstMatch
        if swipeTab.exists {
            swipeTab.tap()
            let pair = app.descendants(matching: .any)["swipe.pair"].waitForExistence(timeout: 20)
            metric("swipe_pair_available", pair)
            metric("swipe_notice_visible", app.descendants(matching: .any)["swipe.notice"].exists)
        }
        // Relaunch: cached index should make Home ready quickly and not crash.
        app.terminate()
        let relaunch = Date()
        app.launch()
        let ready = app.descendants(matching: .any)["activity.overview"].waitForExistence(timeout: 60)
            || app.buttons["dashboard.scan"].exists
        metric("relaunch_to_home_s", String(format: "%.1f", Date().timeIntervalSince(relaunch)))
        XCTAssertTrue(ready)
    }

    func test2_PauseReturnsPromptly() {
        guard launchToHome(), startDefaultScan() else { XCTFail("Could not start scan"); return }
        let pause = app.buttons["scan.banner.pause"]
        guard pause.waitForExistence(timeout: 30) else { metric("pause_button_found", false); return }
        Thread.sleep(forTimeInterval: 8)
        guard pause.exists else { metric("scan_finished_before_pause", true); return }
        let t = Date()
        pause.tap()
        let gone = NSPredicate(format: "exists == false")
        let result = XCTWaiter().wait(for: [expectation(for: gone, evaluatedWith: pause)], timeout: 20)
        metric("pause_to_stop_s", String(format: "%.1f", Date().timeIntervalSince(t)))
        metric("pause_effective", result == .completed || app.descendants(matching: .any)["scan.pausereason"].exists)
    }

    private func startScope(_ scope: String) -> Bool {
        let change = app.buttons["scan.changeScope"]
        for _ in 0..<6 where !change.isHittable { app.swipeUp() }
        guard change.waitForExistence(timeout: 10) else { metric("change_scope_found", false); return false }
        change.tap()
        let option = app.buttons["scan.scope.\(scope)"]
        guard option.waitForExistence(timeout: 10) else { metric("scope_option_found", false); return false }
        option.tap()
        return true
    }

    func test3_Latest2000ScanCompletesResponsively() {
        guard launchToHome(), startScope("start2000") else { XCTFail("Could not start 2,000 scan"); return }
        let start = Date()
        let banner = app.descendants(matching: .any)["scan.banner"]
        metric("s2000_banner_appeared", banner.waitForExistence(timeout: 30))
        var maxProbe: TimeInterval = 0, probes = 0, slow = 0
        while banner.exists && Date().timeIntervalSince(start) < 1_800 {
            let p = probeLatency(); probes += 1; maxProbe = max(maxProbe, p); if p > 2 { slow += 1 }
            Thread.sleep(forTimeInterval: 5)
        }
        metric("s2000_elapsed_s", String(format: "%.1f", Date().timeIntervalSince(start)))
        metric("s2000_finished", !banner.exists)
        metric("s2000_app_running", app.state == .runningForeground)
        metric("s2000_probe_count", probes); metric("s2000_probe_max_s", String(format: "%.2f", maxProbe)); metric("s2000_probe_slow", slow)
        metric("s2000_categories_visible", app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'category.'")).count)
        // Category tiles carry app-authored labels with counts only (no asset data).
        let tiles = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'category.'"))
        for i in 0..<tiles.count {
            let t = tiles.element(boundBy: i)
            metric("s2000_category[\(t.identifier)]", "\"\(t.label.replacingOccurrences(of: "\n", with: " "))\"")
        }
        let swipeTab = app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Swipe'")).firstMatch
        if swipeTab.exists {
            swipeTab.tap()
            metric("s2000_swipe_pair_available", app.descendants(matching: .any)["swipe.pair"].waitForExistence(timeout: 20))
            // App-authored state only (never free text that could one day carry photo metadata).
            metric("s2000_swipe_notice_visible", app.descendants(matching: .any)["swipe.notice"].exists)
        }
        XCTAssertEqual(app.state, .runningForeground, "App must not crash during a 2,000-item scan")
        XCTAssertFalse(banner.exists, "2,000-item scan did not finish within 30 minutes")
        XCTAssertLessThan(maxProbe, 5, "Main thread appeared blocked for >5 s")
    }

    func test4_PauseDuring2000ScanReturnsPromptly() {
        guard launchToHome(), startScope("start2000") else { XCTFail("Could not start 2,000 scan"); return }
        let pause = app.buttons["scan.banner.pause"]
        guard pause.waitForExistence(timeout: 30) else { metric("p2000_pause_found", false); XCTFail("No pause button"); return }
        Thread.sleep(forTimeInterval: 15)
        guard pause.exists else { metric("p2000_finished_before_pause", true); return }
        let t = Date()
        pause.tap()
        let result = XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: pause)], timeout: 20)
        let elapsed = Date().timeIntervalSince(t)
        metric("p2000_pause_to_stop_s", String(format: "%.1f", elapsed))
        metric("p2000_pause_effective", result == .completed)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertLessThan(elapsed, 10, "Pause should stop the scan within 10 s")
    }

    /// End-to-end real-PhotoKit delete of ONE screenshot copy inside the dedicated simulator (never the Mac
    /// library). Exercises the performChanges change block on Photos' own queue (Swift 6 isolation) and the
    /// whole tray → confirm → Apple prompt → receipt path.
    func test5_DeleteOneScreenshotEndToEnd() throws {
        // Deletes a photo copy and confirms Apple's prompt automatically: a second, delete-specific opt-in.
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLEANSLATE_REALLIB_ALLOW_DELETE"] == "1",
                          "Real-library deletion needs CLEANSLATE_REALLIB_ALLOW_DELETE=1 on the dedicated simulator.")
        guard launchToHome(), startScope("start2000") else { XCTFail("Could not start scan"); return }
        let banner = app.descendants(matching: .any)["scan.banner"]
        _ = banner.waitForExistence(timeout: 30)
        let start = Date()
        while banner.exists && Date().timeIntervalSince(start) < 900 { Thread.sleep(forTimeInterval: 3) }
        let category = app.buttons["category.screenshots"]
        for _ in 0..<6 where !category.isHittable { app.swipeUp() }
        guard category.waitForExistence(timeout: 10) else { metric("e2e_screenshots_category", false); XCTFail("no screenshots category"); return }
        category.tap()
        let tile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile.'")).firstMatch
        guard tile.waitForExistence(timeout: 10) else { metric("e2e_tile_found", false); XCTFail("no screenshot tile"); return }
        tile.tap()
        app.buttons["approval.approve"].tap()
        while !app.buttons["tray.button"].exists, app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() }
        app.buttons["tray.button"].tap()
        guard app.buttons["tray.delete"].waitForExistence(timeout: 10) else { XCTFail("no tray delete"); return }
        app.buttons["tray.delete"].tap()
        if app.buttons["confirm.continue"].waitForExistence(timeout: 5) { app.buttons["confirm.continue"].tap() }
        // Apple's deletion prompt (system UI). Tap its destructive button wherever it is hosted.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        var prompted = false
        let deadline = Date().addingTimeInterval(20)
        while !prompted && Date() < deadline {
            for host in [springboard, app!] {
                let button = host.alerts.buttons["Delete"]
                if button.exists { button.tap(); prompted = true; break }
            }
            if !prompted { Thread.sleep(forTimeInterval: 0.5) }
        }
        metric("e2e_apple_prompt_seen", prompted)
        let receipt = app.buttons["receipt.done"].waitForExistence(timeout: 30)
        metric("e2e_receipt_shown", receipt)
        metric("e2e_app_running", app.state == .runningForeground)
        if let bytes = app.staticTexts["receipt.bytes"].exists ? app.staticTexts["receipt.bytes"].label : nil { metric("e2e_receipt_bytes", "\"\(bytes)\"") }
        XCTAssertEqual(app.state, .runningForeground, "App must not crash in the real delete path")
        XCTAssertTrue(prompted, "Apple's prompt should appear")
        XCTAssertTrue(receipt, "A receipt should follow a confirmed deletion")
    }
}
