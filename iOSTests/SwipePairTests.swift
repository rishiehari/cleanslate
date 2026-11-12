import XCTest
import CleanSlateCore
@testable import CleanSlate

@MainActor
final class SwipePairTests: XCTestCase {
    private var library: FakePhotoLibrary!
    private var cleaning: CleaningViewModel!
    private var analyzer: FakePhotoAnalyzer!

    override func setUp() async throws {
        library = FakePhotoLibrary()
        cleaning = CleaningViewModel(library: library, tray: DeletionTray(fileURL: nil), store: try LibraryStore(path: nil))
        analyzer = FakePhotoAnalyzer()
        cleaning.analyzer = analyzer
        for id in ["a", "b", "c", "d"] {
            library.add(id, content: id)
            analyzer.descriptions[id] = .init(faceCount: 1, text: ["same"])
        }
    }

    private func group(_ id: String = "near-1", _ members: [String] = ["a", "b"], evidence: [PairEvidence]? = nil) -> PhotoReviewGroup {
        let source = library.reviewSet(members)
        return PhotoReviewGroup(id: id, kind: .similar, keeper: source.keeper, candidates: source.candidates,
                                evidence: evidence ?? source.evidence, verifiedCandidateBytes: [:])
    }

    private func pair(_ group: PhotoReviewGroup? = nil) async -> SwipePairModel {
        let source = group ?? self.group()
        cleaning.seedGroupsForUITesting([source])
        let pair = SwipePairModel(group: source, cleaning: cleaning)
        await pair.keepLeft.loadWarnings()
        await pair.keepRight.loadWarnings()
        return pair
    }

    func testStartsUnmarkedAndEitherOrientationRequiresExplicitApproval() async {
        let pair = await pair()
        XCTAssertNil(pair.side)
        XCTAssertTrue(pair.review.draft.deleteIDs.isEmpty)
        XCTAssertFalse(pair.approve())
        pair.choose(.left)
        XCTAssertEqual(pair.review.draft.deleteIDs, ["b"])
        XCTAssertEqual(pair.review.draft.keepIDs, ["a"])
        XCTAssertTrue(cleaning.tray.isEmpty)
        pair.choose(.right)
        XCTAssertEqual(pair.review.draft.deleteIDs, ["a"])
        XCTAssertEqual(pair.review.draft.keepIDs, ["b"])
        XCTAssertTrue(pair.approve())
        XCTAssertEqual(cleaning.tray.entries.first?.id, "near-1")
        XCTAssertEqual(cleaning.tray.entries.first?.selectedIDs, ["a"])
        XCTAssertEqual(cleaning.tray.entries.first?.manuallyReviewedIDs, ["a"])
        XCTAssertEqual(cleaning.tray.entries.first?.effectiveKeeperIDs, ["b"])
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testLeftChoiceApprovesOnlyRightAndTrayUndoReturnsPair() async {
        let pair = await pair()
        pair.choose(.left)
        XCTAssertTrue(pair.approve())
        XCTAssertEqual(cleaning.tray.entries.first?.selectedIDs, ["b"])
        XCTAssertTrue(SwipePairFeed.groups(in: cleaning).isEmpty)
        cleaning.tray.undo()
        XCTAssertEqual(SwipePairFeed.groups(in: cleaning).map(\.id), ["near-1"])
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testKeepBothClearsChoiceAndSkipsWithoutTrayEntryAndUndoRestoresPair() async {
        let pair = await pair()
        pair.choose(.right)
        pair.keepBoth()
        XCTAssertNil(pair.side)
        XCTAssertTrue(pair.keepLeft.draft.deleteIDs.isEmpty)
        XCTAssertTrue(pair.keepRight.draft.deleteIDs.isEmpty)
        XCTAssertTrue(cleaning.tray.reviewedGroupIDs.contains("near-1"))
        XCTAssertTrue(cleaning.tray.isEmpty)
        XCTAssertTrue(library.deleteCalls.isEmpty)
        cleaning.tray.undo()
        XCTAssertTrue(pair.isCurrent)
    }

    func testUndoChoiceRestoresUnmarkedPairWithoutReviewing() async {
        let pair = await pair()
        pair.choose(.left)
        pair.undoChoice()
        XCTAssertNil(pair.side)
        XCTAssertTrue(pair.review.draft.deleteIDs.isEmpty)
        XCTAssertTrue(cleaning.tray.reviewedGroupIDs.isEmpty)
    }

    func testAllPreservationFlagsBlockEitherDeletionDirection() async {
        for flag in PreservationFlag.allCases {
            for protectedID in ["a", "b"] {
                library.update("a", flags: protectedID == "a" ? [flag] : [])
                library.update("b", flags: protectedID == "b" ? [flag] : [])
                let pair = await pair()
                pair.choose(protectedID == "a" ? .right : .left)
                XCTAssertTrue(pair.review.draft.deleteIDs.isEmpty, "\(flag) on \(protectedID)")
                XCTAssertFalse(pair.approve(), "\(flag) on \(protectedID)")
                XCTAssertNotNil(pair.review.notice)
                XCTAssertTrue(cleaning.tray.isEmpty)
            }
        }
    }

    func testExtraPeopleWarningGatesBothDirectionsAndAcknowledgementDoesNotTransfer() async {
        analyzer.descriptions["a"] = .init(faceCount: 2, text: ["left"])
        analyzer.descriptions["b"] = .init(faceCount: 3, text: ["right"])
        let pair = await pair()
        pair.choose(.left)
        XCTAssertEqual(pair.review.warningPromptFor, "b")
        XCTAssertFalse(pair.approve())
        pair.review.acknowledgeAndDelete("b")
        pair.choose(.right)
        XCTAssertEqual(pair.review.warningPromptFor, "a")
        XCTAssertFalse(pair.approve())
        pair.review.acknowledgeAndDelete("a")
        XCTAssertTrue(pair.approve())
    }

    func testUnavailableAnalysisRequiresAcknowledgement() async {
        analyzer.descriptions = [:]
        let pair = await pair()
        pair.choose(.right)
        XCTAssertTrue(pair.review.couldntCompare.contains("a"))
        XCTAssertFalse(pair.approve())
        pair.review.acknowledgeAndDelete("a")
        XCTAssertTrue(pair.approve())
    }

    func testIncompleteAnalysisBlocksBothOrientations() {
        let group = group()
        cleaning.seedGroupsForUITesting([group])
        let pair = SwipePairModel(group: group, cleaning: cleaning)
        for side in [SwipePairModel.Side.left, .right] {
            pair.choose(side)
            XCTAssertTrue(pair.review.draft.deleteIDs.isEmpty)
            XCTAssertFalse(pair.approve())
        }
    }

    func testChangedRemovedOrProtectedSnapshotBlocksApprovalBeforeTray() async {
        for mutation in 0..<3 {
            library.add("a", content: "a")
            library.add("b", content: "b")
            let pair = await pair()
            pair.choose(.right)
            if mutation == 0 { library.update("a", revision: "v2") }
            if mutation == 1 { library.assets["b"] = nil }
            if mutation == 2 { library.update("a", flags: [.favorite]) }
            XCTAssertFalse(pair.approve())
            XCTAssertTrue(cleaning.tray.isEmpty)
        }
    }

    func testReplacementGroupAndRevokedAccessInvalidateHeldChoice() async {
        let pair = await pair()
        pair.choose(.left)
        cleaning.seedGroupsForUITesting([group("near-1", ["a", "c"])])
        XCTAssertFalse(pair.approve())
        cleaning.seedGroupsForUITesting([group()])
        library.authorization = .denied
        XCTAssertFalse(pair.approve())
        XCTAssertTrue(SwipePairFeed.groups(in: cleaning).isEmpty)
        XCTAssertTrue(cleaning.tray.isEmpty)
    }

    func testFeedUsesOnlyOriginalDirectTwoPhotoPairsAndDeterministicDisjointMembership() {
        let valid = group()
        let overlapping = group("near-2", ["a", "c"])
        let separate = group("near-3", ["c", "d"])
        let noProof = group("near-none", evidence: [])
        let wrongProof = group("near-wrong", evidence: [.init(first: "a", second: "b", relation: .uncertain)])
        let foreignProof = group("near-foreign", evidence: [.init(first: "a", second: "c", relation: .visuallySimilar)])
        let unique = group("near-unique", evidence: [.init(first: "a", second: "b", relation: .visuallySimilar, uniqueContentDetected: true)])
        let sequence = group("seq-1")
        let big = group("near-big", ["a", "b", "c"])
        let exact = library.exactGroup(keeper: "a", copies: ["b"])
        cleaning.seedGroupsForUITesting([big, sequence, noProof, wrongProof, foreignProof, unique, exact, separate, overlapping, valid])
        XCTAssertEqual(SwipePairFeed.groups(in: cleaning).map(\.id), ["near-1", "near-3"])
        XCTAssertFalse(SwipePairFeed.eligible(group("near-self", ["a", "a"])))
        library.assets["b"]?.snapshot.isVideo = true
        XCTAssertFalse(SwipePairFeed.eligible(group()))
    }

    func testAnyTrayMembershipExcludesPairAndBlocksHeldChoice() async {
        let pair = await pair()
        pair.choose(.left)
        cleaning.tray.approve(group: group("other", ["a", "c"]), selected: ["c"], manuallyReviewed: ["c"], keepers: ["a"])
        XCTAssertTrue(SwipePairFeed.groups(in: cleaning).isEmpty)
        XCTAssertFalse(pair.approve())
        cleaning.tray.clear()
        cleaning.tray.approveStandalone(items: [.init(snapshot: library.assets["b"]!.snapshot, verifiedBytes: nil)])
        XCTAssertTrue(SwipePairFeed.groups(in: cleaning).isEmpty)
        XCTAssertFalse(pair.approve())
    }

    func testApprovedPairUsesNormalCommitAndRejectsRevisionChangedAfterApproval() async throws {
        let pair = await pair()
        pair.choose(.right)
        XCTAssertTrue(pair.approve())
        let entry = try XCTUnwrap(cleaning.tray.entries.first)
        library.update("a", revision: "changed")
        let coordinator = PhotoDeletionCoordinator(library: library, networkPolicy: cleaning.networkPolicy)
        do {
            _ = try await coordinator.commit(group: entry.group, selected: entry.selectedIDs,
                                             manuallyReviewed: entry.manuallyReviewedIDs, keeperIDs: entry.effectiveKeeperIDs)
            XCTFail("A changed photo must be rejected")
        } catch { XCTAssertTrue(library.deleteCalls.isEmpty) }
    }
}
