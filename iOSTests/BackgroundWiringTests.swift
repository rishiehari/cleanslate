import XCTest
import CleanSlateCore
@testable import CleanSlate

/// F03.10: background wiring — registration happens at launch, and a scan of more than 500 items
/// requests continued processing (exactly once per scan). The simulator has no BG runtime, so the
/// DEBUG seam asserts the logic; the real BGTaskScheduler submit stays untested here by design.
@MainActor
final class BackgroundWiringTests: XCTestCase {
    override func setUp() {
        BackgroundScanning.continuedProcessingRequestCount = 0
    }

    func testSmallScanDoesNotRequestContinuedProcessing() async throws {
        let library = FakePhotoLibrary()
        for i in 0..<10 { library.add("p\(i)", content: "c\(i)") }
        let model = try ScanTestRig.model(library: library)
        await model.runScan()
        XCTAssertEqual(BackgroundScanning.continuedProcessingRequestCount, 0, "500 items or fewer stays a foreground scan")
    }

    func testLargeScanRequestsContinuedProcessingOnce() async throws {
        let library = FakePhotoLibrary()
        library.addBulk(count: 1_200, plantedExactPairs: 0)
        library.disableThumbnails = true
        let model = try ScanTestRig.model(library: library)
        await model.runScan()
        XCTAssertEqual(model.statistics.photosEnumerated, 1_200)
        XCTAssertEqual(BackgroundScanning.continuedProcessingRequestCount, 1, "one request per scan")
        // A second scan requests again.
        await model.runScan()
        XCTAssertEqual(BackgroundScanning.continuedProcessingRequestCount, 2)
    }
}
