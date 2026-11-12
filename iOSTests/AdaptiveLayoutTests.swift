import XCTest
@testable import CleanSlate

final class AdaptiveLayoutTests: XCTestCase {
    func testNarrowWindowStacksComparison() {
        XCTAssertFalse(AdaptiveLayout.usesHorizontalComparison(width: 390, accessibilityText: false))
    }

    func testWideWindowUsesEqualSideBySidePhotos() {
        XCTAssertTrue(AdaptiveLayout.usesHorizontalComparison(width: 900, accessibilityText: false))
    }

    func testAccessibilityTextKeepsStackedLabelsEvenInWideWindow() {
        XCTAssertFalse(AdaptiveLayout.usesHorizontalComparison(width: 1366, accessibilityText: true))
    }
}
