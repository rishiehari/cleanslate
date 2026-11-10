import XCTest
import CleanSlateCore
@testable import CleanSlate

/// An analyzer whose answers are released by the test, so the "analysis still running" window can be observed.
@MainActor
final class GatedAnalyzer: PhotoAnalyzer {
    var descriptions: [String: PhotoDescription] = [:]
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var open = false
    func describe(assetID: String) async -> PhotoDescription {
        if !open { await withCheckedContinuation { waiting.append($0) } }
        return descriptions[assetID] ?? PhotoDescription(faceCount: nil, text: nil)
    }
    func release() { open = true; waiting.forEach { $0.resume() }; waiting = [] }
}

/// D1/D2: nothing non-exact is markable until its comparison finished, and a photo that could not be compared needs a look.
@MainActor
final class AnalysisGateTests: XCTestCase {
    private var library: FakePhotoLibrary!

    override func setUp() async throws { library = FakePhotoLibrary() }

    private func model(_ ids: [String], analyzer: PhotoAnalyzer?) -> (GroupReviewModel, DeletionTray) {
        for id in ids { library.add(id, content: id) }
        let tray = DeletionTray(fileURL: nil)
        return (GroupReviewModel(group: library.reviewSet(ids), tray: tray, haptics: HapticsService(), analyzer: analyzer), tray)
    }

    private func same(_ ids: [String]) -> [String: PhotoDescription] {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, PhotoDescription(faceCount: 1, text: ["sign"])) })
    }

    func testTapBeforeAnalysisFinishesDoesNotMark() async {
        let analyzer = GatedAnalyzer(); analyzer.descriptions = same(["a", "b", "c"])
        let (m, _) = model(["a", "b", "c"], analyzer: analyzer)
        let loading = Task { await m.loadWarnings() }
        await Task.yield()
        XCTAssertTrue(m.isCheckingPhotos)
        m.tap("b")
        XCTAssertEqual(m.decision(for: "b"), .undecided)
        XCTAssertEqual(m.notice, GroupReviewModel.stillCheckingNotice)
        XCTAssertFalse(m.canApprove)
        XCTAssertFalse(m.canUndo, "a refused tap leaves no history")
        analyzer.release(); await loading.value
        XCTAssertFalse(m.isCheckingPhotos)
        m.tap("b")
        XCTAssertEqual(m.decision(for: "b"), .delete, "after the check, an unwarned photo can be marked")
    }

    func testMarkTheRestBeforeAnalysisFinishesMarksNothing() async {
        let analyzer = GatedAnalyzer(); analyzer.descriptions = same(["a", "b", "c"])
        let (m, _) = model(["a", "b", "c"], analyzer: analyzer)
        let loading = Task { await m.loadWarnings() }
        await Task.yield()
        m.markEverythingElseForDeletion()
        XCTAssertTrue(m.draft.deleteIDs.isEmpty)
        XCTAssertFalse(m.canApprove)
        m.set("b", to: .delete)
        XCTAssertTrue(m.draft.deleteIDs.isEmpty, "set() is gated the same way")
        analyzer.release(); await loading.value
        m.markEverythingElseForDeletion()
        XCTAssertEqual(m.draft.deleteIDs, ["b", "c"])
    }

    func testAMarkedPhotoThatGainsAWarningIsUnmarked() async {
        let analyzer = FakePhotoAnalyzer()
        analyzer.descriptions = ["a": .init(faceCount: 1, text: ["x"]), "b": .init(faceCount: 4, text: ["x"]), "c": .init(faceCount: 1, text: ["x"])]
        let (m, _) = model(["a", "b", "c"], analyzer: analyzer)
        // Force the unsafe state the gate normally prevents: both marked before warnings exist.
        m.debugForceMark(["b", "c"])
        XCTAssertEqual(m.draft.deleteIDs, ["b", "c"])
        await m.loadWarnings()
        XCTAssertEqual(m.decision(for: "b"), .undecided, "warning arrived: the mark is withdrawn")
        XCTAssertEqual(m.decision(for: "c"), .delete)
        XCTAssertTrue(m.isAwaitingAcknowledgement("b"))
        m.undo()
        XCTAssertNotEqual(m.decision(for: "b"), .delete, "undo cannot bring back an unacknowledged mark")
    }

    func testUnavailableAnalysisRequiresAcknowledgement() async {
        let analyzer = FakePhotoAnalyzer()       // no descriptions: every photo is "could not be determined"
        let (m, _) = model(["a", "b", "c"], analyzer: analyzer)
        await m.loadWarnings()
        XCTAssertTrue(m.couldntCompare.contains("b"))
        XCTAssertTrue(m.isAwaitingAcknowledgement("b"))
        m.tap("b")
        XCTAssertEqual(m.warningPromptFor, "b")
        XCTAssertEqual(m.decision(for: "b"), .undecided)
        m.markEverythingElseForDeletion()
        XCTAssertTrue(m.draft.deleteIDs.isEmpty, "Mark the rest skips photos that could not be compared")
        m.acknowledgeAndDelete("b")
        XCTAssertEqual(m.decision(for: "b"), .delete)
    }

    func testUnavailableKeeperAnalysisAlsoFailsClosed() async {
        let analyzer = FakePhotoAnalyzer()
        analyzer.descriptions = ["b": .init(faceCount: 1, text: ["x"]), "c": .init(faceCount: 1, text: ["x"])]   // keeper "a" missing
        let (m, _) = model(["a", "b", "c"], analyzer: analyzer)
        await m.loadWarnings()
        XCTAssertTrue(m.isAwaitingAcknowledgement("b"))
        XCTAssertTrue(m.isAwaitingAcknowledgement("c"))
    }

    func testExactDuplicatesAreUnaffected() async {
        for id in ["a", "b"] { library.add(id, content: "same") }
        let tray = DeletionTray(fileURL: nil)
        let analyzer = GatedAnalyzer()
        let m = GroupReviewModel(group: library.exactGroup(keeper: "a", copies: ["b"]), tray: tray, haptics: HapticsService(), analyzer: analyzer)
        XCTAssertFalse(m.isCheckingPhotos)
        XCTAssertEqual(m.decision(for: "b"), .delete, "pre-marked from the start")
        XCTAssertTrue(m.canApprove)
        XCTAssertTrue(m.approve())
        XCTAssertEqual(tray.entries.count, 1)
    }

    func testAFavoriteCopyInsideAnExactPairIsNeverDeleted() async throws {
        let (library, _) = FakePhotoLibrary.recent100Scenario(now: Date(timeIntervalSince1970: 1_800_000_000))
        library.add("fav-a", content: "favpair", at: 1_799_000_000)
        library.add("fav-b", content: "favpair", at: 1_799_000_000)
        library.update("fav-b", flags: [.favorite])
        let tray = DeletionTray(fileURL: nil)
        let model = try ScanTestRig.model(library: library, tray: tray)
        await model.runScan()
        XCTAssertFalse(model.groups.isEmpty)
        for group in model.groups {
            let review = GroupReviewModel(group: group, tray: tray)
            XCTAssertFalse(review.draft.deleteIDs.contains("fav-b"), "a favorite copy is never pre-marked")
            review.tap("fav-b")
            XCTAssertFalse(review.draft.deleteIDs.contains("fav-b"))
            if review.canApprove { review.approve() }
        }
        XCTAssertFalse(tray.entries.contains { $0.selectedIDs.contains("fav-b") })
        XCTAssertTrue(library.deleteCalls.isEmpty)
        XCTAssertNotNil(library.assets["fav-b"])
    }
}
