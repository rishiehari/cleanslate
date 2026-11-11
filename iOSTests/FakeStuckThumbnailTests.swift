import XCTest
import CleanSlateCore
@testable import CleanSlate

/// The stuck-thumbnail fake: a PhotoKit callback that never fires, plus in-flight counters.
/// F03.1 contract: the shared Deadline ends the wait on `releaseStuckThumbnails()` AND on
/// cancellation (that is how Cancel finishes a scan) — only a caller that does neither waits
/// out the (test-configurable) deadline.
@MainActor
final class FakeStuckThumbnailTests: XCTestCase {
    typealias Spec = FakePhotoLibrary.RenderSpec


    func testStuckThumbnailHoldsUntilReleaseOrCancellation() async {
        let library = FakePhotoLibrary()
        library.add("a", content: "a", spec: Spec(base: 1)); library.add("b", content: "b", spec: Spec(base: 2))
        library.stuckThumbnailIDs = ["a"]
        let stuck = Task { @MainActor in await library.thumbnail("a", target: 280) }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(library.thumbnailsInFlight, 1)
        let other = await library.thumbnail("b", target: 280)
        XCTAssertNotNil(other, "other assets are unaffected")
        XCTAssertEqual(library.maxThumbnailsInFlight, 2)
        library.releaseStuckThumbnails()
        let releasedImage = await stuck.value
        XCTAssertNotNil(releasedImage, "released: returns a normal picture")
        XCTAssertEqual(library.thumbnailsInFlight, 0)
        let again = await library.thumbnail("a", target: 280)
        XCTAssertNotNil(again, "after release the asset is no longer stuck")

        // F03.1: cancelling the waiting task ends the wait (nil = unavailable, like a cancelled
        // PhotoKit request) — this is what lets Cancel finish a scan with a stuck callback.
        library.stuckThumbnailIDs = ["a"]
        let cancelled = Task { @MainActor in await library.thumbnail("a", target: 280) }
        try? await Task.sleep(for: .milliseconds(100))
        cancelled.cancel()
        let abandoned = await cancelled.value
        XCTAssertNil(abandoned, "cancellation frees the wait (F03.1)")
        XCTAssertEqual(library.thumbnailsInFlight, 0)
        XCTAssertEqual(library.thumbnailTimeouts, 1, "the deadline ending the wait is counted")
        library.releaseStuckThumbnails()
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
