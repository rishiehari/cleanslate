import XCTest
import CleanSlateCore
@testable import CleanSlate

/// F03.6: one feature print per asset (LRU 64) + shared quality cache (LRU 2,000), and a
/// per-request Vision deadline whose expiry is a Vision failure, never a match.
@MainActor
final class VisionCacheTests: XCTestCase {
    func testFeaturePrintComputedOncePerAsset() async throws {
        // One 8-photo burst: the whole pair working set fits the 64-entry LRU, so every print is
        // computed exactly once. (Re-prints across huge libraries are bounded by the F03.11 formula.)
        let library = FakePhotoLibrary.burstHeavy(count: 20, burstShare: 0.6, burstLength: 8, seed: 7)
        let visual = FakeVisualAnalyzer()
        let model = try ScanTestRig.model(library: library, visual: visual)
        await model.runScan()
        XCTAssertEqual(visual.maxPrintsOfOnePicture, 1, "every print is computed once per asset")
        XCTAssertGreaterThan(visual.printCalls, 0)
        // Quality = face + aesthetics per photo: at most 2 Vision calls per asset, computed once.
        XCTAssertLessThanOrEqual(visual.qualityCalls, 2 * 20, "one quality pass (2 requests) per asset")
    }

    /// M1: stuck QUALITY requests (face/aesthetics) also honor the deadline: the review-set scan
    /// completes, the expiry is counted as a Vision failure, and the set is still built.
    func testStuckVisionQualityExpiresAndCountsFailure() async throws {
        let library = FakePhotoLibrary()
        let spec = FakePhotoLibrary.RenderSpec(base: 21)
        for frame in 0..<3 { library.add("q-\(frame)", content: "\(frame)", at: Int64(1_000 + frame), burst: "QB", spec: spec) }
        let visual = FakeVisualAnalyzer()
        visual.stuckTokens = [spec.token]
        let model = try ScanTestRig.model(library: library, visual: visual)
        let began = Date()
        await model.runScan()
        let elapsed = Date().timeIntervalSince(began)
        XCTAssertLessThan(elapsed, 13, "the quality deadline abandoned the stuck request instead of waiting forever (\(String(format: "%.1f", elapsed))s)")
        XCTAssertGreaterThan(model.statistics.visionFailures, 0, "the abandoned quality request is counted as a Vision failure")
        XCTAssertGreaterThan(model.statistics.reviewSetsFound, 0, "the review set is still built with default signals")
    }

    /// M1: stop() during a stuck quality request finishes promptly (deadline cancel path).
    func testStopDuringStuckVisionQualityFinishesWithinTwoSeconds() async throws {
        let library = FakePhotoLibrary()
        let spec = FakePhotoLibrary.RenderSpec(base: 22)
        for frame in 0..<3 { library.add("s-\(frame)", content: "\(frame)", at: Int64(1_000 + frame), burst: "SB", spec: spec) }
        let visual = FakeVisualAnalyzer()
        visual.stuckTokens = [spec.token]
        let model = try ScanTestRig.model(library: library, visual: visual)
        model.scanAllForTesting()
        let stuck = await waitUntil(timeout: 10) { model.scanCounters.snapshot.phase == .vision }
        XCTAssertTrue(stuck, "the scan entered the vision phase (stuck quality request in flight)")
        let began = Date()
        model.stop()
        let finished = await waitUntil(timeout: 2) { !model.isScanning }
        XCTAssertTrue(finished, "stop() during a stuck quality request finished in \(String(format: "%.1f", Date().timeIntervalSince(began)))s")
        visual.releaseStuckVision()
    }

    private func waitUntil(timeout: TimeInterval, poll: Duration = .milliseconds(50), _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: poll)
        }
        return condition()
    }

    /// A Vision request that never returns within 10 s is abandoned: the pair is not compared,
    /// the failure is counted, and the scan still completes.
    func testStuckVisionRequestIsAbandonedAndCounted() async throws {
        let library = FakePhotoLibrary()
        let spec = FakePhotoLibrary.RenderSpec(base: 3)
        library.add("v-a", content: "a", at: 1_000_000, spec: spec)
        library.add("v-b", content: "b", at: 9_000_000, spec: spec)
        let visual = FakeVisualAnalyzer()
        visual.delayPerCall = .seconds(15)               // past the 10 s per-request deadline
        let model = try ScanTestRig.model(library: library, visual: visual)
        let began = Date()
        await model.runScan()
        let elapsed = Date().timeIntervalSince(began)
        XCTAssertLessThan(elapsed, 14, "the deadline abandoned the stuck request instead of waiting it out")
        XCTAssertGreaterThan(model.statistics.visionFailures, 0, "the abandoned request is counted as a Vision failure")
        XCTAssertTrue(model.groups.filter({ $0.kind == .similar }).isEmpty, "an unverified pair is never matched")
    }

    func testQualityCacheIsSharedBetweenPhases() async throws {
        // Two photos that appear BOTH in a review set (burst) and as a near pair: quality must be
        // computed once, and the print at most once.
        let library = FakePhotoLibrary()
        let spec = FakePhotoLibrary.RenderSpec(base: 9)
        for frame in 0..<3 {
            library.add("both-\(frame)", content: "\(frame)", at: Int64(1_000 + frame), burst: "B", spec: spec)
        }
        let visual = FakeVisualAnalyzer()
        let model = try ScanTestRig.model(library: library, visual: visual)
        await model.runScan()
        XCTAssertLessThanOrEqual(visual.maxPrintsOfOnePicture, 1)
        XCTAssertLessThanOrEqual(visual.qualityCalls, 2 * 3, "face+aesthetics per asset, shared across both phases")
    }
}
