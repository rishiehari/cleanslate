import XCTest
import CleanSlateCore
@testable import CleanSlate

/// F03 owner rule 4: strictly one asset in flight, and the fingerprint thumbnails are 128 px.
@MainActor
final class ScanConcurrencyTests: XCTestCase {
    func testStrictlyOneAssetInFlight() async throws {
        let library = FakePhotoLibrary()
        library.yieldInThumbnails = true        // overlap would be observable if it happened
        for i in 0..<60 { library.add("p\(i)", content: "c\(i)") }
        let model = try ScanTestRig.model(library: library)
        await model.runScan()
        XCTAssertEqual(library.maxThumbnailsInFlight, 1, "no two thumbnail requests may overlap in this version")
    }

    func testFingerprintsUse128pxThumbnails() async throws {
        let library = FakePhotoLibrary()
        for i in 0..<10 { library.add("p\(i)", content: "c\(i)") }
        let model = try ScanTestRig.model(library: library)
        await model.runScan()
        XCTAssertGreaterThan(library.fingerprintThumbnailCalls, 0)
        XCTAssertTrue(library.requestedThumbnailTargets.contains(128), "fingerprint requests target 128 px")
        XCTAssertFalse(library.requestedThumbnailTargets.contains(280), "the old 280-px fingerprint target is gone")
    }
}
