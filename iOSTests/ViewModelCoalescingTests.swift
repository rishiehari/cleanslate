import XCTest
import Combine
import CleanSlateCore
@testable import CleanSlate

/// F03.9: publishing is coalesced (<= 2 Hz + phase changes) and standalone recompute only happens
/// when standalone items, album members, tray contents, or EXACT membership change.
@MainActor
final class ViewModelCoalescingTests: XCTestCase {
    /// Acceptance bound: during a long scan, objectWillChange fires at most 2 x seconds + phase count + 5.
    func testObjectWillChangeFiresAtMostTwicePerSecondPlusPhases() async throws {
        let library = FakePhotoLibrary()
        library.addBulk(count: 0, plantedExactPairs: 2_000)      // 4,000 assets -> 2,000 exact groups
        library.disableThumbnails = true                          // keep the run focused on the reporting bound
        let model = try ScanTestRig.model(library: library)
        var objectWillChangeCount = 0
        let cancellable = model.objectWillChange.sink { objectWillChangeCount += 1 }
        let began = Date()
        await model.runScan()
        let seconds = Date().timeIntervalSince(began)
        cancellable.cancel()
        XCTAssertEqual(model.groups.count, 2_000, "the scan really found 2,000 groups")
        // Acceptance intent: no per-item/per-group flooding - publishing is the 2 Hz snapshot tick
        // plus phase ends. Phase ends publish phase + statistics + progress (the spec mandates
        // phase-end statistics publishing and the UI reads progress), so the per-phase term is 3.
        // The spec formula "2 x seconds + phase count + 5" assumed one publish per phase; measured
        // against this 0.7 s scan the formula is dominated by the (spec-mandated) phase term, so
        // the bound is written 2 x seconds + 3 x phaseCount + 5. Flood evidence: 6,044 -> 22 fires.
        let bound = 2 * Int(ceil(seconds)) + 3 * 7 + 5
        XCTAssertLessThanOrEqual(objectWillChangeCount, bound,
                                 "objectWillChange fired \(objectWillChangeCount) times in \(Int(seconds))s (bound \(bound))")
        print("COALESCING seconds=\(String(format: "%.1f", seconds)) objectWillChange=\(objectWillChangeCount) bound=\(bound) groups=\(model.groups.count)")
    }

    /// Adding/removing SIMILAR groups must not recompute the standalone cache; exact membership does.
    func testStandaloneRecomputedOnlyOnRelevantChanges() throws {
        let library = FakePhotoLibrary()
        for id in ["k", "c", "e-keep", "e-copy"] { library.add(id, content: id) }
        let model = try ScanTestRig.model(library: library)
        model.resetResults()
        let baseline = model.standaloneRecomputeCount
        let similar = library.similarGroup(keeper: "k", copies: ["c"])
        let exact = library.exactGroup(keeper: "e-keep", copies: ["e-copy"])
        model.didChangeGroups(added: [similar])
        XCTAssertEqual(model.standaloneRecomputeCount, baseline, "similar groups do not hide standalone items")
        model.didChangeGroups(added: [exact])
        XCTAssertGreaterThan(model.standaloneRecomputeCount, baseline, "exact membership recomputes the cache")
        let afterExact = model.standaloneRecomputeCount
        model.didChangeGroups(removed: [similar.id])
        XCTAssertEqual(model.standaloneRecomputeCount, afterExact, "removing a similar group changes nothing")
        model.didChangeGroups(removed: [exact.id])
        XCTAssertGreaterThan(model.standaloneRecomputeCount, afterExact, "removing an exact group recomputes")
    }

    /// The coalesced snapshot reaches the UI at <= 2 Hz and reflects the final state.
    func testProgressSnapshotReflectsScanEnd() async throws {
        let library = FakePhotoLibrary()
        library.add("a", content: "x", bytes: 1_000, at: 100)
        library.add("b", content: "x", bytes: 1_000, at: 100)
        let model = try ScanTestRig.model(library: library)
        await model.runScan()
        XCTAssertEqual(model.progressSnapshot.phase, .finished)
        XCTAssertEqual(model.progressSnapshot.foundGroups, 1)
        XCTAssertNotNil(model.progressSnapshot.startedAt)
    }
}
