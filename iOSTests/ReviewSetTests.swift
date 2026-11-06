import XCTest
import Photos
import CleanSlateCore
@testable import CleanSlate

@MainActor
final class ReviewSetTests: XCTestCase {
    private var library: FakePhotoLibrary!
    private var coordinator: PhotoDeletionCoordinator!

    override func setUp() async throws {
        library = FakePhotoLibrary()
        coordinator = PhotoDeletionCoordinator(library: library,
            networkPolicy: NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { false }))
    }

    private func makeModel() throws -> CleaningViewModel {
        CleaningViewModel(library: library, tray: DeletionTray(fileURL: nil),
                          networkPolicy: NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { false }),
                          store: try LibraryStore(path: nil))
    }

    // MARK: Review sets from a scan

    func testABurstBecomesOneReviewSetWithAllPairsLinked() async throws {
        for n in 0..<4 { library.add("burst\(n)", content: "same-scene", at: 5_000 + Int64(n), burst: "B1") }
        library.add("other", content: "different", at: 90_000)
        let model = try makeModel(); await model.runScan()
        let sets = model.groups(in: .similar)
        XCTAssertEqual(sets.count, 1)
        let set = try XCTUnwrap(sets.first)
        XCTAssertEqual(set.all.count, 4)
        XCTAssertEqual(set.evidence.count, 6, "4 photos = 6 pairs, so any photo can be the one kept")
        XCTAssertEqual(model.statistics.reviewSetsFound, 1)
    }

    func testQuickLookAlikeShotsFormASetButAFarAwayShotDoesNot() async throws {
        library.add("q1", content: "scene", at: 8_000); library.add("q2", content: "scene", at: 8_001); library.add("q3", content: "scene", at: 8_002)
        library.add("later", content: "scene", at: 80_000)
        let model = try makeModel(); await model.runScan()
        let set = try XCTUnwrap(model.groups(in: .similar).first { $0.all.contains { $0.id == "q1" } })
        XCTAssertEqual(Set(set.all.map(\.id)), ["q1", "q2", "q3"])
    }

    func testExactCopiesAreNeverAlsoPutInAReviewSet() async throws {
        library.add("e1", content: "twin", at: 6_000); library.add("e2", content: "twin", at: 6_000)
        let model = try makeModel(); await model.runScan()
        XCTAssertEqual(model.groups(in: .exact).count, 1)
        XCTAssertTrue(model.groups(in: .similar).isEmpty, "claimed by the exact group")
    }

    func testReviewSetNeverPreselectsAnything() async throws {
        for n in 0..<3 { library.add("s\(n)", content: "scene", at: 5_000 + Int64(n)) }
        let model = try makeModel(); await model.runScan()
        let set = try XCTUnwrap(model.groups(in: .similar).first)
        XCTAssertTrue(SafetyPolicy.evaluate(set.coreCluster).preselected.isEmpty)
        XCTAssertEqual(SafetyPolicy.evaluate(set.coreCluster).reviewOnly, Set(set.candidates.map(\.id)))
    }

    func testReviewSetGroupIdIsStableAcrossScans() async throws {
        for n in 0..<3 { library.add("s\(n)", content: "scene", at: 5_000 + Int64(n)) }
        let first = try makeModel(); await first.runScan()
        let second = try makeModel(); await second.runScan()
        XCTAssertEqual(first.groups(in: .similar).map(\.id), second.groups(in: .similar).map(\.id))
    }

    // MARK: Multi-keeper commits

    func testKeepingTwoAndDeletingOneDeletesOnlyThatOne() async throws {
        for id in ["a", "b", "c"] { library.add(id, content: id) }
        let group = library.reviewSet(["a", "b", "c"])
        let result = try await coordinator.commit(group: group, selected: ["c"], manuallyReviewed: ["c"], keeperIDs: ["a", "b"])
        XCTAssertEqual(library.deleteCalls, [["c"]])
        XCTAssertNotNil(library.assets["a"]); XCTAssertNotNil(library.assets["b"])
        XCTAssertEqual(result.verifiedRemoved, 1)
    }

    func testTheSuggestedKeeperCanBeDeletedWhenTheUserKeepsAnotherPhoto() async throws {
        for id in ["a", "b", "c"] { library.add(id, content: id) }
        let group = library.reviewSet(["a", "b", "c"])          // "a" is the suggested keeper
        _ = try await coordinator.commit(group: group, selected: ["a"], manuallyReviewed: ["a"], keeperIDs: ["c"])
        XCTAssertEqual(library.deleteCalls, [["a"]])
    }

    func testCommitRefusesWhenTheChosenKeeperIsNotInTheGroupOrOverlapsTheSelection() async {
        for id in ["a", "b", "x"] { library.add(id, content: id) }
        let group = library.reviewSet(["a", "b"])
        do { _ = try await coordinator.commit(group: group, selected: ["b"], manuallyReviewed: ["b"], keeperIDs: ["x"]); XCTFail("foreign keeper") }
        catch { XCTAssertTrue(library.deleteCalls.isEmpty) }
        do { _ = try await coordinator.commit(group: group, selected: ["b"], manuallyReviewed: ["b"], keeperIDs: ["a", "b"]); XCTFail("keeper == selection") }
        catch { XCTAssertTrue(library.deleteCalls.isEmpty) }
        do { _ = try await coordinator.commit(group: group, selected: ["b"], manuallyReviewed: ["b"], keeperIDs: []); XCTFail("no keeper") }
        catch { XCTAssertTrue(library.deleteCalls.isEmpty) }
    }

    func testDeletionStillNeedsTheUsersOwnLookForSimilarShots() async {
        for id in ["a", "b"] { library.add(id, content: id) }
        let group = library.reviewSet(["a", "b"])
        do { _ = try await coordinator.commit(group: group, selected: ["b"], manuallyReviewed: [], keeperIDs: ["a"]); XCTFail("needs manual review") }
        catch { XCTAssertTrue(library.deleteCalls.isEmpty) }
    }

    func testExactGroupWithTwoKeepersRehashesEveryPhoto() async throws {
        for id in ["a", "b", "c"] { library.add(id, content: "same") }
        let group = library.exactGroup(keeper: "a", copies: ["b", "c"])
        library.assets["b"]?.digests = [FakePhotoLibrary.digest("different")]       // a kept photo no longer matches
        do { _ = try await coordinator.commit(group: group, selected: ["c"], manuallyReviewed: [], keeperIDs: ["a", "b"]); XCTFail() }
        catch { XCTAssertTrue(library.deleteCalls.isEmpty) }
    }

    // MARK: Review screen model

    private func reviewModel(_ ids: [String], analyzer: PhotoAnalyzer? = nil) -> (GroupReviewModel, DeletionTray) {
        for id in ids { library.add(id, content: id) }
        let tray = DeletionTray(fileURL: nil)
        return (GroupReviewModel(group: library.reviewSet(ids), tray: tray, haptics: HapticsService(), analyzer: analyzer), tray)
    }

    func testApprovePassesTheUsersKeepersToTheTray() {
        let (model, tray) = reviewModel(["a", "b", "c"])
        model.set("b", to: .keep)             // keep a AND b
        model.tap("c")                        // delete c
        XCTAssertTrue(model.approve())
        XCTAssertEqual(tray.entries[0].keeperIDs, ["a", "b"])
        XCTAssertEqual(tray.entries[0].selectedIDs, ["c"])
    }

    func testWarningsLoadAndTappingAWarnedPhotoAsksFirst() async {
        let analyzer = FakePhotoAnalyzer()
        analyzer.descriptions = ["a": .init(faceCount: 2, text: ["sign"]), "b": .init(faceCount: 3, text: ["sign"]), "c": .init(faceCount: 2, text: ["sign"])]
        let (model, _) = reviewModel(["a", "b", "c"], analyzer: analyzer)
        await model.loadWarnings()
        XCTAssertEqual(model.warnings["b"], [.differentPeople])
        XCTAssertNil(model.warnings["c"])
        model.tap("b")
        XCTAssertEqual(model.warningPromptFor, "b", "asks before marking a photo that shows an extra person")
        XCTAssertEqual(model.decision(for: "b"), .undecided)
        model.acknowledgeAndDelete("b")
        XCTAssertEqual(model.decision(for: "b"), .delete)
        XCTAssertNil(model.warningPromptFor)
    }

    func testMarkTheRestSkipsWarnedPhotosAndNeverApproves() async {
        let analyzer = FakePhotoAnalyzer()
        analyzer.descriptions = ["a": .init(faceCount: 1, text: nil), "b": .init(faceCount: 2, text: nil), "c": .init(faceCount: 1, text: nil)]
        let (model, tray) = reviewModel(["a", "b", "c"], analyzer: analyzer)
        await model.loadWarnings()
        model.markEverythingElseForDeletion()
        XCTAssertEqual(model.decision(for: "c"), .delete)
        XCTAssertEqual(model.decision(for: "b"), .undecided, "warned photo needs a look first")
        XCTAssertTrue(tray.entries.isEmpty, "marking is not approving")
    }

    func testUndoRestoresTheLastTwentyActionsAndNoMore() {
        let ids = (0..<30).map { "p\($0)" }
        let (model, _) = reviewModel(ids)
        for id in ids.dropFirst() { model.tap(id) }                    // 29 changes
        for _ in 0..<GroupReviewModel.historyLimit { model.undo() }
        XCTAssertFalse(model.canUndo, "only the last \(GroupReviewModel.historyLimit) are remembered")
        XCTAssertEqual(ids.dropFirst().filter { model.decision(for: $0) == .delete }.count, 9)
    }

    func testBlockedTapsDoNotPolluteTheUndoHistory() {
        let (model, _) = reviewModel(["a", "b"])
        model.tap("a")                                              // can't remove the last Keep
        XCTAssertFalse(model.canUndo)
        model.tap("b"); XCTAssertTrue(model.canUndo)
        model.undo(); XCTAssertEqual(model.decision(for: "b"), .undecided)
    }

    func testTrayEntryIgnoresChangesToUndecidedBystanders() async throws {
        let model = try makeModel()
        for n in 0..<4 { library.add("g\(n)", content: "scene", at: 5_000 + Int64(n)) }
        await model.runScan()
        let group = try XCTUnwrap(model.groups(in: .similar).first)
        let ids = group.all.map(\.id)
        model.tray.approve(group: group, selected: [ids[1]], manuallyReviewed: [ids[1]], keepers: [ids[0]])
        library.update(ids[3], revision: "changed")                  // not kept, not deleted: irrelevant to this approval
        await model.processLibraryChange()
        XCTAssertNil(model.tray.needsAttention[group.id])
    }
}
