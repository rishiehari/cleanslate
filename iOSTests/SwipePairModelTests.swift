import XCTest
import CleanSlateCore
@testable import CleanSlate

@MainActor
final class SwipePairModelTests: XCTestCase {
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

    private func similarGroup(_ id: String = "near-1", _ members: [String] = ["a", "b"], evidence: [PairEvidence]? = nil) -> PhotoReviewGroup {
        let source = library.reviewSet(members)
        return PhotoReviewGroup(id: id, kind: .similar, keeper: source.keeper, candidates: source.candidates,
                                evidence: evidence ?? source.evidence, verifiedCandidateBytes: [:])
    }

    private func exactGroup(_ id: String = "exact-1", _ members: [String] = ["a", "b"], evidence: [PairEvidence]? = nil) -> PhotoReviewGroup {
        let source = library.reviewSet(members)
        return PhotoReviewGroup(id: id, kind: .exact, keeper: source.keeper, candidates: source.candidates,
                                evidence: evidence ?? [.init(first: members[0], second: members[1], relation: .exactResources, completeResourceEquality: true)],
                                verifiedCandidateBytes: [:])
    }

    private func similarPair(_ group: PhotoReviewGroup? = nil) async -> SwipePairModel {
        let source = group ?? self.similarGroup()
        cleaning.seedGroupsForUITesting([source])
        let pair = SwipePairModel(group: source, cleaning: cleaning)
        await pair.keepLeft.loadWarnings()
        await pair.keepRight.loadWarnings()
        return pair
    }

    private func exactPair(_ group: PhotoReviewGroup? = nil) async -> SwipePairModel {
        let source = group ?? self.exactGroup()
        cleaning.seedGroupsForUITesting([source])
        let pair = SwipePairModel(group: source, cleaning: cleaning)
        await pair.keepLeft.loadWarnings()
        await pair.keepRight.loadWarnings()
        return pair
    }

    func testExactPairSupport() async {
        let pair = await exactPair()
        XCTAssertTrue(pair.isExactPair)
        XCTAssertEqual(pair.original.kind, .exact)
        
        // Test that exact pairs can be chosen and approved
        pair.choose(.left)
        XCTAssertTrue(pair.approve())
        XCTAssertFalse(pair.isCurrent) // Pair should be marked as reviewed after approval
    }

    func testSimilarPairSupport() async {
        let pair = await similarPair()
        XCTAssertFalse(pair.isExactPair)
        XCTAssertEqual(pair.original.kind, .similar)
        
        // Test that similar pairs can be chosen and approved
        pair.choose(.right)
        XCTAssertTrue(pair.approve())
        XCTAssertFalse(pair.isCurrent) // Pair should be marked as reviewed after approval
    }

    func testUpGestureKeepBoth() async {
        let pair = await similarPair()
        pair.chooseKeepBoth()
        XCTAssertNil(pair.side)
        XCTAssertEqual(pair.choiceType, .keepBoth)
        
        // Should skip without adding to tray
        XCTAssertTrue(cleaning.tray.reviewedGroupIDs.contains("near-1"))
        XCTAssertTrue(cleaning.tray.isEmpty)
    }

    func testChoiceTypeTracking() async {
        let pair = await similarPair()
        
        // Test left choice
        pair.choose(.left)
        XCTAssertEqual(pair.choiceType, .keepLeft)
        XCTAssertEqual(pair.side, .left)
        
        // Test right choice  
        pair.choose(.right)
        XCTAssertEqual(pair.choiceType, .keepRight)
        XCTAssertEqual(pair.side, .right)
        
        // Test keep both
        pair.chooseKeepBoth()
        XCTAssertEqual(pair.choiceType, .keepBoth)
        XCTAssertNil(pair.side)
    }

    func testExactPairWithApproval() async {
        let pair = await exactPair()
        pair.choose(.left)
        XCTAssertTrue(pair.approve())
        
        // Exact pairs should be handled properly in the approval
        let entry = cleaning.tray.entries.first
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.selectedIDs, ["b"])
        XCTAssertEqual(entry?.effectiveKeeperIDs, ["a"])
    }

    func testFeedEligibleExactPairs() {
        // Test that exact pairs are eligible for swipe feed
        let exact = exactGroup()
        XCTAssertTrue(SwipePairFeed.eligible(exact))
        
        // Test that similar pairs are eligible
        let similar = similarGroup()
        XCTAssertTrue(SwipePairFeed.eligible(similar))
        
        // Test that non-eligible pairs are rejected
        let wrongEvidence = similarGroup("near-wrong", evidence: [.init(first: "a", second: "b", relation: .uncertain)])
        XCTAssertFalse(SwipePairFeed.eligible(wrongEvidence))
    }
}