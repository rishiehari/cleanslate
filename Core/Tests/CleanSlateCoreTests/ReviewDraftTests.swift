import XCTest
@testable import CleanSlateCore

final class ReviewDraftTests: XCTestCase {
    private func exact() -> ReviewDraft {
        ReviewDraft(assetIDs: ["k", "c1", "c2"], keeperIDs: ["k"], preMarkedDelete: ["c1", "c2"], protectedIDs: [])
    }
    private func similar() -> ReviewDraft {
        ReviewDraft(assetIDs: ["k", "a", "b"], keeperIDs: ["k"], preMarkedDelete: [], protectedIDs: [])
    }

    func testExactOpensPreMarkedAndCanApprove() {                 // U4
        let d = exact()
        XCTAssertEqual(d.deleteIDs, ["c1", "c2"])
        XCTAssertEqual(d.keepIDs, ["k"])
        XCTAssertTrue(d.canApprove)
    }

    func testSimilarOpensWithNothingMarkedDeleteAndCannotApprove() {  // U4
        let d = similar()
        XCTAssertTrue(d.deleteIDs.isEmpty)
        XCTAssertEqual(d.mark(for: "a"), .undecided)
        XCTAssertFalse(d.canApprove)
    }

    func testTapTogglesUndecidedToDeleteAndBack() {
        var d = similar()
        XCTAssertEqual(d.toggle("a"), .changed(.delete))
        XCTAssertTrue(d.canApprove)
        XCTAssertEqual(d.toggle("a"), .changed(.keep))   // delete -> keep
        XCTAssertFalse(d.canApprove)
    }

    func testCannotRemoveTheLastKeep() {                          // U3
        var d = exact()
        XCTAssertEqual(d.toggle("k"), .blockedLastKeep)
        XCTAssertEqual(d.keepIDs, ["k"])
        // With a second keep it becomes allowed, but never to zero.
        _ = d.toggle("c1")                                        // c1 -> keep
        XCTAssertEqual(d.toggle("k"), .changed(.delete))
        XCTAssertEqual(d.toggle("c1"), .blockedLastKeep)
        XCTAssertFalse(d.keepIDs.isEmpty)
    }

    func testProtectedNeverTogglesAndStaysKept() {                // U3
        var d = ReviewDraft(assetIDs: ["k", "fav"], keeperIDs: ["k"], preMarkedDelete: ["fav"], protectedIDs: ["fav"])
        XCTAssertEqual(d.mark(for: "fav"), .keep, "a protected photo can never be pre-marked for deletion")
        XCTAssertEqual(d.toggle("fav"), .blockedProtected)
        XCTAssertEqual(d.set("fav", to: .delete), .blockedProtected)
        XCTAssertTrue(d.deleteIDs.isEmpty)
        XCTAssertFalse(d.canApprove)
    }

    func testUnknownAsset() {
        var d = exact()
        XCTAssertEqual(d.toggle("nope"), .unknownAsset)
    }

    func testUserMarkedDeleteTracksOnlyUserActions() {
        var d = exact()
        XCTAssertTrue(d.userMarkedDelete.isEmpty, "pre-marked exact copies are not user-compared")
        _ = d.toggle("c1")                       // delete -> keep
        XCTAssertEqual(d.userMarkedDelete, [], "toggled back to keep")
        _ = d.toggle("c1")                       // keep -> delete again, now a user decision
        XCTAssertEqual(d.userMarkedDelete, ["c1"])
        var s = similar()
        _ = s.toggle("a")
        XCTAssertEqual(s.userMarkedDelete, ["a"])
    }

    func testSetRespectsLastKeepRule() {
        var d = similar()
        XCTAssertEqual(d.set("k", to: .undecided), .blockedLastKeep)
        XCTAssertEqual(d.set("a", to: .delete), .changed(.delete))
    }

    /// Property: whatever sequence of taps happens, a group never ends with zero Keep photos and
    /// protected photos are never marked Delete.
    func testRandomTapSequencesNeverBreakInvariants() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let ids = (0..<6).map { "p\($0)" }
            let protected: Set<String> = Set(ids.filter { _ in Int.random(in: 0..<5, using: &rng) == 0 })
            var d = ReviewDraft(assetIDs: ids, keeperIDs: ["p0"], preMarkedDelete: Set(ids.dropFirst()), protectedIDs: protected)
            for _ in 0..<30 { _ = d.toggle(ids.randomElement(using: &rng)!) }
            XCTAssertFalse(d.keepIDs.isEmpty)
            XCTAssertTrue(d.deleteIDs.isDisjoint(with: protected))
        }
    }
}
