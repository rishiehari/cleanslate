import XCTest

/// Captures the main screens as PNGs for design review. Runs only when
/// TEST_RUNNER_CAPTURE_DIR is set (e.g. `make screens`), otherwise it is skipped.
final class ScreenshotTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func captureDir() throws -> String {
        guard let dir = ProcessInfo.processInfo.environment["CAPTURE_DIR"], !dir.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_CAPTURE_DIR to capture screenshots")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func shot(_ name: String, in dir: String) {
        sleep(1)
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.firstMatch
        if button.waitForExistence(timeout: 3) { button.tap() }
    }

    private func backToHome(_ app: XCUIApplication) {
        while !app.buttons["tray.button"].exists, app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
        }
    }

    private func run(appearance: XCUIDevice.Appearance, suffix: String, size: String? = nil) throws {
        let dir = try captureDir()
        XCUIDevice.shared.appearance = appearance
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingFakeLibrary", "-skipOnboarding"]
        if let size { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        app.launch()
        XCTAssertTrue(app.buttons["category.exact"].waitForExistence(timeout: 8))
        shot("01-home-\(suffix)", in: dir)
        app.buttons["category.exact"].tap()
        _ = app.buttons["group.test-ex1-keep"].waitForExistence(timeout: 5)
        shot("02-inbox-\(suffix)", in: dir)
        app.buttons["group.test-ex1-keep"].tap()
        _ = app.buttons["approval.approve"].waitForExistence(timeout: 5)
        shot("03-review-exact-\(suffix)", in: dir)
        back(app); back(app)
        app.buttons["category.similar"].tap()
        app.buttons["group.test-sim1-a"].tap()
        _ = app.buttons["approval.approve"].waitForExistence(timeout: 5)
        app.buttons["tile.sim1-b"].tap()
        shot("04-review-similar-\(suffix)", in: dir)
        app.buttons["review.compare"].tap()
        _ = app.buttons["compare.done"].waitForExistence(timeout: 5)
        shot("05-compare-\(suffix)", in: dir)
        app.buttons["compare.done"].tap()
        app.buttons["approval.approve"].tap()
        backToHome(app)
        app.buttons["category.exact"].tap()
        app.buttons["group.test-ex1-keep"].tap()
        app.buttons["approval.approve"].tap()
        backToHome(app)
        app.buttons["tray.button"].tap()
        _ = app.buttons["tray.delete"].waitForExistence(timeout: 5)
        shot("06-tray-\(suffix)", in: dir)
        app.buttons["tray.delete"].tap()
        _ = app.buttons["confirm.continue"].waitForExistence(timeout: 5)
        shot("07-confirm-\(suffix)", in: dir)
        app.buttons["confirm.continue"].tap()
        _ = app.buttons["receipt.done"].waitForExistence(timeout: 8)
        sleep(2)
        shot("08-receipt-\(suffix)", in: dir)
    }

    func testCaptureLight() throws { try run(appearance: .light, suffix: "light") }
    func testCaptureDark() throws { try run(appearance: .dark, suffix: "dark") }
    func testCaptureLargeText() throws {
        try run(appearance: .light, suffix: "ax3", size: "UICTContentSizeCategoryAccessibilityL")
    }
}
