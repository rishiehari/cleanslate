import XCTest
import CleanSlateCore
@testable import CleanSlate

/// Reproductions of the "Scan All stalls at ~7,000 photos" hang (docs/HANG_RCA.md) on the fake library.
/// Each documents a known bug with `XCTExpectFailure`; F03 removes the expectation so the same assert must pass.
@MainActor
final class HangReproTests: XCTestCase {
    private func waitUntil(timeout: TimeInterval, poll: Duration = .milliseconds(100), _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: poll)
        }
        return condition()
    }

    // H1b: pairs and review sets are compared with per-asset caches and tier caps, so Vision work is
    // bounded by what the scan actually examines. F03.11: the spec formula and pair cap are plain asserts.
    func testVisionWorkIsBoundedOnABurstHeavyLibrary() async throws {
        let photos = 7_000
        let library = FakePhotoLibrary.burstHeavy(count: photos, burstShare: 0.6, burstLength: 8, seed: 42)
        let visual = FakeVisualAnalyzer()
        let model = try ScanTestRig.model(library: library, visual: visual)
        model.scan()
        let started = await waitUntil(timeout: 10) { model.isScanning }
        XCTAssertTrue(started, "the scan started")
        let finished = await waitUntil(timeout: 240) { !model.isScanning }
        let calls = visual.calls
        let reviewSetPhotos = model.statistics.visionReviewSetPhotos
        let pairsCompared = model.statistics.visionPairsCompared
        let allowed = 4 * (reviewSetPhotos + 2 * pairsCompared)
        print("HANGREPRO vision photos=\(photos) calls=\(calls) allowed=\(allowed) reviewSetPhotos=\(reviewSetPhotos) pairsCompared=\(pairsCompared) prints=\(visual.printCalls) quality=\(visual.qualityCalls) maxPrintsOfOnePicture=\(visual.maxPrintsOfOnePicture) pairsConsidered=\(model.statistics.candidatePairsConsidered) reviewSets=\(model.statistics.reviewSetsFound) scanFinishedByItself=\(finished)")
        XCTAssertTrue(finished, "the fake scan completes on its own")
        XCTAssertLessThanOrEqual(calls, allowed, "Vision calls <= 4 x (review-set photos + 2 x pairs compared)")
        XCTAssertLessThanOrEqual(visual.maxPrintsOfOnePicture, 8,
            "prints are computed once per asset within the 64-entry LRU working set (uncached engine: 44)")
        XCTAssertLessThanOrEqual(model.statistics.candidatePairsConsidered, 2 * ScanLimits().candidatePairCap,
            "candidate pairs stay within the tier-capped queries (near + moments)")
    }

    // H4: a PhotoKit callback that never fires. Cancel must still finish the scan quickly.
    func testCancelFinishesEvenWhenAThumbnailNeverReturns() async throws {
        let library = FakePhotoLibrary.burstHeavy(count: 300, burstShare: 0.3, burstLength: 6, seed: 3)
        library.stuckThumbnailIDs = ["u0"]
        let model = try ScanTestRig.model(library: library)
        model.scan()
        let stuck = await waitUntil(timeout: 20) { library.thumbnailsInFlight > 0 && library.maxThumbnailsInFlight > 0 && model.statistics.photosEnumerated > 0 }
        XCTAssertTrue(stuck, "the scan reached the stuck thumbnail")
        let began = Date()
        model.stop()
        let finishedWithinFiveSeconds = await waitUntil(timeout: 5) { !model.isScanning }
        print("HANGREPRO stuckThumbnail cancelFinished=\(finishedWithinFiveSeconds) waited=\(String(format: "%.1f", Date().timeIntervalSince(began)))s inFlight=\(library.thumbnailsInFlight)")
        // F03.1: thumbnail requests have a client-side deadline and honor cancellation, so Cancel finishes.
        XCTAssertTrue(finishedWithinFiveSeconds, "Cancel did not finish the scan within 5 s")
        defer { library.releaseStuckThumbnails() }
        library.releaseStuckThumbnails()
        let ended = await waitUntil(timeout: 60) { !model.isScanning }
        XCTAssertTrue(ended, "once released, the scan ends (test hygiene)")
    }
}

extension XCTExpectedFailure.Options {
    /// Strict: once the bug is fixed the assertion passes, and an expected failure that does not fail is itself a test failure,
    /// so the fix forces this expectation to be removed.
    static func strictForRemoval() -> XCTExpectedFailure.Options {
        let options = XCTExpectedFailure.Options()
        options.isStrict = true
        return options
    }
}
