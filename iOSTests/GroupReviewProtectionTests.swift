import XCTest
import CleanSlateCore
@testable import CleanSlate

/// N05 C5: a review draft opened before a rule existed cannot approve a protected photo into the tray.
@MainActor
final class GroupReviewProtectionTests: XCTestCase {
    private var library: FakePhotoLibrary!
    private var tray: DeletionTray!
    private var gate: StaticProtectionGate!

    override func setUp() async throws {
        library = FakePhotoLibrary()
        tray = DeletionTray(fileURL: nil)
        gate = StaticProtectionGate()
        library.add("k", content: "same", at: 1_000); library.add("c", content: "same", at: 1_000)
    }

    private func model(viaTray: Bool = false) -> GroupReviewModel {
        let group = library.exactGroup(keeper: "k", copies: ["c"], bytes: 10)
        if viaTray { tray.protectionGate = gate; return GroupReviewModel(group: group, tray: tray, haptics: HapticsService()) }
        return GroupReviewModel(group: group, tray: tray, haptics: HapticsService(), protection: gate)
    }

    func testApproveFromStaleDraftIsBlocked() {
        let review = model()
        XCTAssertTrue(review.canApprove, "exact copies are pre-marked when the draft opens")
        gate.protectedIDs = ["c"]                                   // the rule arrives after the draft was built
        XCTAssertFalse(review.approve())
        XCTAssertTrue(tray.entries.isEmpty)
        XCTAssertEqual(review.notice, TrayChecker.protectedByRuleReason)
    }

    func testStaleDraftIsBlockedThroughTheTrayGateToo() {
        let review = model(viaTray: true)
        gate.protectedIDs = ["c"]
        XCTAssertFalse(review.approve())
        XCTAssertTrue(tray.entries.isEmpty)
    }

    func testUnprotectedGroupApproves() {
        let review = model()
        XCTAssertTrue(review.approve())
        XCTAssertEqual(tray.entries.count, 1)
    }

    func testProtectedKeeperStillApproves() {
        let review = model()
        gate.protectedIDs = ["k"]
        XCTAssertTrue(review.approve())
        XCTAssertEqual(tray.entries.count, 1)
    }

    func testRulesNotReadyBlocksApproval() {
        for state: ProtectionAvailability in [.loading, .unavailable("x"), .lost] {
            gate.availability = .ready              // each draft is opened while the rules are fine (C6 locks drafts opened while not ready)
            let review = model()
            gate.availability = state
            XCTAssertFalse(review.approve(), "\(state)")
            XCTAssertNotNil(review.notice)
        }
        gate.availability = .ready
        gate.pendingWrites = 1
        XCTAssertFalse(model().approve(), "a pending write also blocks")
        XCTAssertTrue(tray.entries.isEmpty)
    }

    func testProtectionBlockDoesNotWithdrawTheDraft() {
        let review = model()
        gate.protectedIDs = ["c"]
        XCTAssertFalse(review.approve())
        gate.protectedIDs = []
        XCTAssertTrue(review.approve(), "once the rule is gone the user may approve again")
    }

    func testSwipeApproveIsBlockedForAProtectedPhotoInEitherOrientation() async {
        let cleaning = CleaningViewModel(library: library, tray: tray, store: try! LibraryStore(path: nil), protection: gate)
        let analyzer = FakePhotoAnalyzer()
        for id in ["k", "c"] { analyzer.descriptions[id] = .init(faceCount: 1, text: ["same"]) }
        cleaning.analyzer = analyzer
        let source = library.reviewSet(["k", "c"])
        let group = PhotoReviewGroup(id: "near-1", kind: .similar, keeper: source.keeper, candidates: source.candidates,
                                     evidence: source.evidence, verifiedCandidateBytes: [:])
        cleaning.seedGroupsForUITesting([group])
        for side in [SwipePairModel.Side.left, .right] {
            let pair = SwipePairModel(group: group, cleaning: cleaning)
            await pair.keepLeft.loadWarnings(); await pair.keepRight.loadWarnings()
            pair.choose(side)
            // Protect whichever photo this orientation would delete.
            gate.protectedIDs = [pair.review.group.candidates[0].id]
            XCTAssertFalse(pair.approve(), "side \(side)")
            XCTAssertTrue(tray.entries.isEmpty)
            gate.protectedIDs = []
        }
    }

    func testSwipeProtectedKeeperAllowsDeletingTheOther() async {
        let cleaning = CleaningViewModel(library: library, tray: tray, store: try! LibraryStore(path: nil), protection: gate)
        let analyzer = FakePhotoAnalyzer()
        for id in ["k", "c"] { analyzer.descriptions[id] = .init(faceCount: 1, text: ["same"]) }
        cleaning.analyzer = analyzer
        let source = library.reviewSet(["k", "c"])
        let group = PhotoReviewGroup(id: "near-1", kind: .similar, keeper: source.keeper, candidates: source.candidates,
                                     evidence: source.evidence, verifiedCandidateBytes: [:])
        cleaning.seedGroupsForUITesting([group])
        let pair = SwipePairModel(group: group, cleaning: cleaning)
        await pair.keepLeft.loadWarnings(); await pair.keepRight.loadWarnings()
        pair.choose(.left)                                           // keep the keeper, delete the other
        gate.protectedIDs = [pair.review.group.keeper.id]            // the photo that is kept is protected: fine
        XCTAssertTrue(pair.approve())
        XCTAssertEqual(tray.entries.count, 1)
    }
}
