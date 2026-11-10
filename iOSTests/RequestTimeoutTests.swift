import XCTest
import CleanSlateCore
@testable import CleanSlate

/// Client-side deadlines (F03.1) on the fake library: a request whose callback never fires must
/// time out fail-closed — "couldn't check", never a match, and it must not block Cancel.
@MainActor
final class RequestTimeoutTests: XCTestCase {
    private func waitUntil(timeout: TimeInterval, poll: Duration = .milliseconds(100), _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: poll)
        }
        return condition()
    }

    /// Safety negative: a digest that never returns is "unverifiable" and must NOT form an exact group.
    func testStuckDigestTimesOutAndNeverFormsAnExactGroup() async throws {
        let library = FakePhotoLibrary()
        library.add("keep", content: "same-bytes", bytes: 1_000, at: 100)
        library.add("copy", content: "same-bytes", bytes: 1_000, at: 100)
        library.stuckDigestIDs = ["copy"]
        library.digestTimeout = 0.3
        let model = try ScanTestRig.model(library: library)
        await model.runScan()
        XCTAssertEqual(model.statistics.exactAssetsUnverifiable, 1, "the timed-out digest is counted as couldn't-check")
        XCTAssertTrue(model.groups.filter({ $0.kind == .exact }).isEmpty,
                      "no exact group may form from a pair whose digest timed out")
        XCTAssertEqual(library.digestTimeouts, 1)
    }

    func testStuckVideoSizeTimesOutAndStaysUnknown() async throws {
        let library = FakePhotoLibrary()
        library.add("vid", content: "vid", at: 100, isVideo: true, duration: 30, size: 50_000_000)
        library.stuckSizeIDs = ["vid"]
        library.sizeTimeout = 0.3
        let model = try ScanTestRig.model(library: library)
        await model.runScan()
        XCTAssertEqual(library.sizeTimeouts, 1)
        let item = model.standaloneItems.first { $0.id == "vid" }
        XCTAssertNotNil(item)
        XCTAssertNil(item?.verifiedBytes, "a timed-out size is unknown, never guessed")
    }

    /// Vision that throws (e.g. its own deadline) is a failure count, not silently a match.
    func testFailingVisionOnAPairIsCountedNotMatched() async throws {
        let library = FakePhotoLibrary()
        // Same scene, same dhash -> near pair; different times/names -> no exact bucket, no review set.
        let spec = FakePhotoLibrary.RenderSpec(base: 7)
        library.add("near-a", content: "a", at: 1_000_000, spec: spec)
        library.add("near-b", content: "b", at: 9_000_000, spec: spec)
        let visual = FakeVisualAnalyzer()
        visual.failTokens = [spec.token]
        let model = try ScanTestRig.model(library: library, visual: visual)
        await model.runScan()
        XCTAssertGreaterThan(model.statistics.visionFailures, 0, "the failed print is counted")
        XCTAssertTrue(model.groups.filter({ $0.kind == .similar }).isEmpty, "a failed comparison forms no similar group")
    }

    /// Slowness alone (within the deadline) does not break matching: the pair still compares and groups.
    func testSlowVisionStillCompares() async throws {
        let library = FakePhotoLibrary()
        let spec = FakePhotoLibrary.RenderSpec(base: 11)
        library.add("slow-a", content: "a", at: 1_000_000, spec: spec)
        library.add("slow-b", content: "b", at: 9_000_000, spec: spec)
        let visual = FakeVisualAnalyzer()
        visual.delayPerCall = .milliseconds(30)
        let model = try ScanTestRig.model(library: library, visual: visual)
        await model.runScan()
        XCTAssertEqual(model.groups.filter({ $0.kind == .similar }).count, 1, "slow-but-successful Vision still groups the pair")
    }
}
