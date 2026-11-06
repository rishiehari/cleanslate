import XCTest
import UIKit
@testable import CleanSlate

final class VisualFeaturesTests: XCTestCase {
    func testIdenticalImageFingerprintsMatch() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 90))
        let image = renderer.image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 120, height: 90))
            UIColor.white.setFill(); context.fill(CGRect(x: 12, y: 15, width: 50, height: 31))
        }
        let a = VisualFeatures.differenceHash(image)
        let b = VisualFeatures.differenceHash(image)
        XCTAssertNotNil(a)
        XCTAssertEqual(a,b)
    }

    func testFeaturePrintDistanceNearZeroForSameBitmap() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 224, height: 224))
        let image = renderer.image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 224, height: 224))
            UIColor.white.setFill(); context.fill(CGRect(x: 20, y: 75, width: 180, height: 60))
        }
        guard let first = VisualFeatures.printFeature(image),
              let second = VisualFeatures.printFeature(image),
              let distance = VisualFeatures.distance(first, second) else {
            XCTFail("Vision should produce valid feature prints on supported devices")
            return
        }
        XCTAssertLessThan(distance, 0.00001)
    }
}
