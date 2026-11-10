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

    // H1b: pairs and review sets are compared without a per-asset cache, so Vision work grows faster than the library.
    func testVisionWorkIsBoundedOnABurstHeavyLibrary() async throws {
        let photos = 7_000
        let library = FakePhotoLibrary.burstHeavy(count: photos, burstShare: 0.6, burstLength: 8, seed: 42)
        let visual = FakeVisualAnalyzer()
        let model = try ScanTestRig.model(library: library, visual: visual)
        // One feature print and one quality pass (face + aesthetics) per photo is the most a cached engine needs.
        let bound = 3 * photos
        model.scan()
        let started = await waitUntil(timeout: 10) { model.isScanning }
        XCTAssertTrue(started, "the scan started")
        let exceeded = await waitUntil(timeout: 240) { visual.calls > bound || !model.isScanning }
        let calls = visual.calls
        let finished = !model.isScanning
        model.stop()
        _ = await waitUntil(timeout: 30) { !model.isScanning }
        print("HANGREPRO vision photos=\(photos) calls=\(calls) bound=\(bound) prints=\(visual.printCalls) quality=\(visual.qualityCalls) scanFinishedByItself=\(finished) pairsConsidered=\(model.statistics.candidatePairsConsidered) reviewSets=\(model.statistics.reviewSetsFound) exceeded=\(exceeded)")
        XCTAssertLessThanOrEqual(calls, bound, "total Vision calls (a regression guard that holds today)")
        XCTAssertTrue(finished, "the fake scan completes on its own")
        // F03: "every print computed once per asset". Today a photo that sits in several candidate pairs is printed again for each.
        let worst = visual.maxPrintsOfOnePicture
        print("HANGREPRO vision maxPrintsOfOnePicture=\(worst)")
        XCTExpectFailure("fixed by F03: no per-asset feature-print cache, so a photo is re-printed for every pair", options: .strictForRemoval()) {
            XCTAssertLessThanOrEqual(worst, 1, "one picture was feature-printed \(worst) times")
        }
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
