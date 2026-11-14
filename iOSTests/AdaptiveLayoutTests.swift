import XCTest
@testable import CleanSlate

final class AdaptiveLayoutTests: XCTestCase {
    func testProtectionInspectorReservesReadableListSpaceAndCollapsesForAccessibility() {
        XCTAssertFalse(AdaptiveLayout.showsProtectionInspector(width: 650, accessibilityText: false))
        XCTAssertTrue(AdaptiveLayout.showsProtectionInspector(width: 900, accessibilityText: false))
        XCTAssertFalse(AdaptiveLayout.showsProtectionInspector(width: 900, accessibilityText: true))
    }

    func testQueueNeedsEnoughRoomForBothQueueAndReview() {
        XCTAssertFalse(AdaptiveLayout.showsReviewQueue(width: 800, accessibilityText: false))
        XCTAssertTrue(AdaptiveLayout.showsReviewQueue(width: 1024, accessibilityText: false))
        XCTAssertFalse(AdaptiveLayout.showsReviewQueue(width: 1366, accessibilityText: true))
    }

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
