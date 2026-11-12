import XCTest
import UIKit

/// Run on iPad with the synthetic library; no real PhotoKit access.
@MainActor
final class IPadLayoutUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testComparisonRotationPreservesChoiceWithoutApproving() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad layout coverage") }
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingFakeLibrary", "-uiTestingSwipe", "-skipOnboarding"]
        app.launch()
        let swipe = app.buttons["Swipe n Save"].firstMatch
        XCTAssertTrue(swipe.waitForExistence(timeout: 8))
        swipe.tap()
        XCTAssertTrue(app.buttons["swipe.left"].waitForExistence(timeout: 8))
        app.buttons["swipe.left"].tap()
        app.buttons["swipe.compare"].tap()
        XCTAssertTrue(app.buttons["compare.done"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["compare.done"].waitForExistence(timeout: 5))
        app.buttons["compare.done"].tap()
        XCTAssertTrue(app.buttons["swipe.approve"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["swipe.approve"].isEnabled)
        let probe = app.descendants(matching: .any)["debug.probe"].value as? String ?? ""
        XCTAssertTrue(probe.contains("deleteCalls=0"))
        XCTAssertTrue(probe.contains("tray=0"))
        XCTAssertEqual(app.descendants(matching: .any)["swipe.photo.sw1-right"].value as? String, "Delete")
    }
}
