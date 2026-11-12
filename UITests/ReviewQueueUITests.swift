import XCTest
import UIKit

@MainActor
final class ReviewQueueUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testRotationPreservesUnapprovedDraftAndQueueAdvancesWithSkip() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad queue layout") }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingFakeLibrary", "-skipOnboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["category.exact"].waitForExistence(timeout: 8))
        app.buttons["category.exact"].tap()
        XCTAssertTrue(app.buttons["group.test-ex1-keep"].waitForExistence(timeout: 5))
        app.buttons["group.test-ex1-keep"].tap()
        let queue = app.descendants(matching: .any)["review.queue"].firstMatch
        XCTAssertTrue(queue.waitForExistence(timeout: 5))
        let copy = app.buttons["tile.ex1-copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        XCTAssertTrue(copy.label.hasPrefix("Keep"))
        XCTAssertFalse(app.buttons["approval.approve"].isEnabled)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        XCTAssertTrue(copy.label.hasPrefix("Keep"))
        XCTAssertFalse(app.buttons["approval.approve"].isEnabled)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(queue.waitForExistence(timeout: 5))
        XCTAssertTrue(copy.label.hasPrefix("Keep"))
        app.buttons["approval.skip"].tap()
        XCTAssertTrue(app.navigationBars["2 of 4"].waitForExistence(timeout: 5))
        let probe = app.descendants(matching: .any)["debug.probe"].value as? String ?? ""
        XCTAssertTrue(probe.contains("deleteCalls=0"))
        XCTAssertTrue(probe.contains("tray=0"))
    }
}
