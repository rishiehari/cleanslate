import XCTest
import CleanSlateCore
@testable import CleanSlate

/// The stuck-thumbnail fake: a PhotoKit callback that never fires and ignores cancellation, plus in-flight counters.
@MainActor
final class FakeStuckThumbnailTests: XCTestCase {
    typealias Spec = FakePhotoLibrary.RenderSpec


    func testStuckThumbnailWaitsForReleaseAndIgnoresCancellation() async {
        let library = FakePhotoLibrary()
        library.add("a", content: "a", spec: Spec(base: 1)); library.add("b", content: "b", spec: Spec(base: 2))
        library.stuckThumbnailIDs = ["a"]
        let stuck = Task { @MainActor in await library.thumbnail("a", target: 280) != nil }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(library.thumbnailsInFlight, 1)
        stuck.cancel()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(library.thumbnailsInFlight, 1, "cancellation does not free it, like a PhotoKit callback that never fires")
        let other = await library.thumbnail("b", target: 280)
        XCTAssertNotNil(other, "other assets are unaffected")
        library.releaseStuckThumbnails()
        let gotImage = await stuck.value
        XCTAssertTrue(gotImage, "released: returns a normal picture")
        XCTAssertEqual(library.thumbnailsInFlight, 0)
        XCTAssertEqual(library.maxThumbnailsInFlight, 2)
        let again = await library.thumbnail("a", target: 280)
        XCTAssertNotNil(again, "after release the asset is no longer stuck")
    }

    func testReleaseWithNothingStuckIsHarmless() {
        let library = FakePhotoLibrary()
        library.releaseStuckThumbnails()
        XCTAssertEqual(library.thumbnailsInFlight, 0)
    }

    func testInFlightCounterSeesOverlapOnlyWhenRequestsOverlap() async {
        let library = FakePhotoLibrary()
        for i in 0..<6 { library.add("p\(i)", content: "p\(i)") }
        for i in 0..<6 { _ = await library.thumbnail("p\(i)", target: 280) }
        XCTAssertEqual(library.maxThumbnailsInFlight, 1, "sequential use never exceeds one")
        library.yieldInThumbnails = true
        let tasks = (0..<6).map { i in Task { @MainActor in await library.thumbnail("p\(i)", target: 280) != nil } }
        for task in tasks { let got = await task.value; XCTAssertTrue(got) }
        XCTAssertGreaterThan(library.maxThumbnailsInFlight, 1)
        XCTAssertEqual(library.thumbnailsInFlight, 0)
    }
}
