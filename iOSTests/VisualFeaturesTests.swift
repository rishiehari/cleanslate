import XCTest
import UIKit
@testable import CleanSlate

final class VisualFeaturesTests: XCTestCase {
    private func sampleImage(size: CGSize = CGSize(width: 224, height: 224)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.black.setFill(); context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill(); context.fill(CGRect(x: 20, y: 75, width: 180, height: 60))
        }
    }

    func testIdenticalImageFingerprintsMatch() {
        let image = sampleImage(size: CGSize(width: 120, height: 90))
        let a = VisualFeatures.differenceHash(image)
        let b = VisualFeatures.differenceHash(image)
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b)
    }

    func testDifferentImagesHaveDifferentHashes() {
        let flat = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 90)).image { c in
            UIColor.gray.setFill(); c.fill(CGRect(x: 0, y: 0, width: 120, height: 90))
        }
        XCTAssertNotEqual(VisualFeatures.differenceHash(sampleImage()), VisualFeatures.differenceHash(flat))
    }

    func testSharpnessAndExposureAreNormalized() {
        let (sharp, exposure) = VisualFeatures.sharpnessAndExposure(sampleImage())
        XCTAssertNotNil(sharp); XCTAssertNotNil(exposure)
        XCTAssertTrue((0...1).contains(sharp!)); XCTAssertTrue((0...1).contains(exposure!))
    }

    /// Records the real outcome of Vision on this runtime instead of hiding it.
    func testFeaturePrintOnThisRuntime() async throws {
        let image = sampleImage()
        do {
            let first = try await VisualFeatures.printFeature(image)
            let second = try await VisualFeatures.printFeature(image)
            let distance = try VisualFeatures.distance(first, second)
            XCTAssertLessThan(distance, 0.00001)
        } catch {
            #if targetEnvironment(simulator)
            throw XCTSkip("Vision feature prints unavailable in this simulator: \(error)")
            #else
            XCTFail("Vision feature print failed on device: \(error)")
            #endif
        }
    }
}
