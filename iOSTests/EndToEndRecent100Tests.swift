import XCTest
import CleanSlateCore
@testable import CleanSlate

/// Scan -> review -> approve -> tray -> delete on the fake 100-photo library. A safety regression net for F03-F10.
/// (Full-library scan for now; F04 switches it to the Recent 100 scope.)
@MainActor
final class EndToEndRecent100Tests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func members(_ groups: [PhotoReviewGroup]) -> [Set<String>] { groups.map { Set($0.all.map(\.id)) } }

    func testFullPathScanReviewApproveTrayDelete() async throws {
        let (library, expected) = FakePhotoLibrary.recent100Scenario(now: fixedNow)
        let visual = FakeVisualAnalyzer()
        let tray = DeletionTray(fileURL: nil)
        let model = try ScanTestRig.model(library: library, visual: visual, tray: tray)
        await model.runScan()

        XCTAssertEqual(model.statistics.photosEnumerated, 100)
        // Exact pairs: found as exact groups, pre-marked.
        let exact = model.groups.filter { $0.kind == .exact }
        XCTAssertEqual(Set(members(exact)), Set(expected.exactPairs.map(Set.init)), "exactly the 5 planted pairs")
        XCTAssertEqual(exact.count, 5)
        // Bursts and overlap runs: similar groups, never pre-marked.
        let similar = model.groups.filter { $0.kind == .similar }
        for burst in expected.bursts {
            XCTAssertTrue(members(similar).contains(Set(burst)), "burst \(burst.first ?? "") appears as one review set")
        }
        for run in expected.overlapRuns {
            XCTAssertTrue(members(similar).contains(Set(run)), "overlap run \(run.first ?? "") appears as one review set")
        }
        for group in similar {
            let review = GroupReviewModel(group: group, tray: tray)
            XCTAssertTrue(review.draft.deleteIDs.isEmpty, "similar group \(group.id) opens with nothing marked")
            XCTAssertFalse(review.canApprove, "and cannot be approved until the person marks something")
        }
        // Nothing planted as protected sits inside any group as a deletion candidate.
        let candidateIDs = Set(model.groups.flatMap { $0.candidates.map(\.id) })
        XCTAssertTrue(candidateIDs.isDisjoint(with: expected.protected))
        XCTAssertGreaterThan(visual.calls, 0, "the fake Vision was used, not the real one")

        // Approve every exact group (U1: approving deletes nothing).
        for group in exact {
            let review = GroupReviewModel(group: group, tray: tray)
            XCTAssertEqual(review.draft.deleteIDs.count, 1, "one copy pre-marked per exact pair")
            XCTAssertTrue(review.approve())
        }
        XCTAssertEqual(tray.entries.count, 5)
        XCTAssertTrue(library.deleteCalls.isEmpty, "U1: nothing is deleted by approving")
        XCTAssertEqual(library.assets.count, 100)

        let deleted = await model.deleteTray()
        XCTAssertTrue(deleted)
        XCTAssertEqual(library.deleteCalls.count, 1, "U4: one Apple prompt for the whole tray")
        XCTAssertEqual(library.deleteCalls[0].count, 5)
        XCTAssertEqual(tray.receipt?.verifiedRemoved, 5)
        XCTAssertEqual(library.assets.count, 95)
        for pair in expected.exactPairs {
            XCTAssertEqual(pair.filter { library.assets[$0] != nil }.count, 1, "one of each pair is kept: \(pair)")
        }
        for id in expected.protected { XCTAssertNotNil(library.assets[id], "protected \(id) survives") }
        for id in expected.bursts.flatMap({ $0 }) + expected.overlapRuns.flatMap({ $0 }) + expected.uniques + expected.screenshots {
            XCTAssertNotNil(library.assets[id], "nothing outside the approved pairs is touched: \(id)")
        }
        XCTAssertTrue(tray.entries.isEmpty)
        let history = await model.loadHistory()
        XCTAssertEqual(history.first?.verifiedRemoved, 5, "the receipt was persisted")
    }

    func testScanIsDeterministic() async throws {
        func run() async throws -> [String] {
            let (library, _) = FakePhotoLibrary.recent100Scenario(now: fixedNow)
            let model = try ScanTestRig.model(library: library)
            await model.runScan()
            return model.groups.map(\.id).sorted()
        }
        let first = try await run(), second = try await run()
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second)
    }

    // MARK: Corner cases

    func testEmptyLibrary() async throws {
        let model = try ScanTestRig.model(library: FakePhotoLibrary())
        await model.runScan()
        XCTAssertEqual(model.statistics.photosEnumerated, 0)
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertFalse(model.isScanning)
    }

    func testOnePhoto() async throws {
        let library = FakePhotoLibrary()
        library.add("only", content: "only", spec: .init(base: 1))
        let model = try ScanTestRig.model(library: library)
        await model.runScan()
        XCTAssertEqual(model.statistics.photosEnumerated, 1)
        XCTAssertTrue(model.groups.isEmpty)
    }

    func testAHundredProtectedPhotosAreNeverOfferedForDeletion() async throws {
        let (library, expected) = FakePhotoLibrary.recent100Scenario(now: fixedNow)
        for id in expected.all { library.update(id, flags: [.favorite]) }
        let tray = DeletionTray(fileURL: nil)
        let model = try ScanTestRig.model(library: library, tray: tray)
        await model.runScan()
        XCTAssertFalse(model.groups.isEmpty, "the loop below must have groups to check")
        for group in model.groups {
            let review = GroupReviewModel(group: group, tray: tray)
            XCTAssertTrue(review.draft.deleteIDs.isEmpty, "nothing in a fully protected library is pre-marked")
            XCTAssertFalse(review.canApprove)
            for candidate in group.candidates { review.tap(candidate.id); XCTAssertTrue(review.draft.deleteIDs.isEmpty, "and tapping cannot mark a favorite") }
        }
        XCTAssertTrue(library.deleteCalls.isEmpty)
        XCTAssertEqual(library.assets.count, 100)
        XCTAssertTrue(tray.entries.isEmpty)
    }

    func testAllThumbnailsUnavailableStillFindsExactCopiesAndNativeBurstsButNotLookAlikes() async throws {
        let (library, expected) = FakePhotoLibrary.recent100Scenario(now: fixedNow)
        library.unavailableThumbnailIDs = Set(expected.all)
        let tray = DeletionTray(fileURL: nil)
        let model = try ScanTestRig.model(library: library, tray: tray)
        await model.runScan()
        XCTAssertEqual(model.groups.filter { $0.kind == .exact }.count, 5, "exact copies are found from file bytes, not pictures")
        let similar = model.groups.filter { $0.kind == .similar }
        XCTAssertEqual(Set(members(similar)), Set(expected.bursts.map(Set.init)), "native bursts need no pictures; time-based runs do")
        for group in similar { XCTAssertTrue(GroupReviewModel(group: group, tray: tray).draft.deleteIDs.isEmpty) }
        XCTAssertEqual(model.statistics.cloudOnlyOrUnavailable, 100)
        XCTAssertFalse(model.isScanning)
    }

    func testVisionFailingEverywhereStillFinishesAndKeepsExactCopies() async throws {
        let (library, expected) = FakePhotoLibrary.recent100Scenario(now: fixedNow)
        let visual = FakeVisualAnalyzer()
        visual.failAll = true
        let tray = DeletionTray(fileURL: nil)
        let model = try ScanTestRig.model(library: library, visual: visual, tray: tray)
        await model.runScan()
        XCTAssertEqual(model.groups.filter { $0.kind == .exact }.count, 5)
        XCTAssertTrue(model.statistics.visionUnavailable)
        XCTAssertGreaterThan(model.statistics.reviewSetsFound, 0)
        for group in model.groups where group.kind == .similar {
            XCTAssertTrue(GroupReviewModel(group: group, tray: tray).draft.deleteIDs.isEmpty)
        }
        XCTAssertEqual(library.assets.count, 100)
        _ = expected
    }

    // MARK: Negatives

    func testAFavoriteInsideABurstIsNeverMarked() async throws {
        let (library, expected) = FakePhotoLibrary.recent100Scenario(now: fixedNow)
        let burst = expected.bursts[0]
        library.update(burst[3], flags: [.favorite])
        let tray = DeletionTray(fileURL: nil)
        let model = try ScanTestRig.model(library: library, tray: tray)
        await model.runScan()
        let group = try XCTUnwrap(model.groups.first { Set($0.all.map(\.id)) == Set(burst) })
        let review = GroupReviewModel(group: group, tray: tray)
        review.markEverythingElseForDeletion()
        XCTAssertFalse(review.draft.deleteIDs.contains(burst[3]), "the favorite is not marked by the helper")
        review.tap(burst[3])
        XCTAssertFalse(review.draft.deleteIDs.contains(burst[3]), "nor by tapping it")
        if case .protected = review.decision(for: burst[3]) {} else if group.keeper.id != burst[3] { XCTFail("expected the favorite to be shown as protected") }
    }

    func testExtraSubjectFramesAreNeverPreMarked() async throws {
        let library = FakePhotoLibrary()
        var ids: [String] = []
        for frame in 0..<6 {
            let id = "f\(frame)"
            library.add(id, content: id, at: 1_700_000_000 + Int64(frame), burst: "b1",
                        spec: .init(base: 9, shiftX: frame % 2, extraSubject: frame == 4))
            ids.append(id)
        }
        let tray = DeletionTray(fileURL: nil)
        let model = try ScanTestRig.model(library: library, tray: tray)
        await model.runScan()
        let group = try XCTUnwrap(model.groups.first)
        XCTAssertEqual(group.kind, .similar)
        let review = GroupReviewModel(group: group, tray: tray)
        XCTAssertTrue(review.draft.deleteIDs.isEmpty, "a frame with a person entering is never pre-marked")
        XCTAssertEqual(Set(group.all.map(\.id)), Set(ids))
        XCTAssertFalse(model.groups.isEmpty)

        // The warning path: the frame with the extra person shows a different face count, so it needs a look before it can be marked.
        let analyzer = FakePhotoAnalyzer()
        for id in ids { analyzer.descriptions[id] = .init(faceCount: id == "f4" ? 2 : 1, text: []) }
        let checked = GroupReviewModel(group: group, tray: tray, haptics: HapticsService(), analyzer: analyzer)
        await checked.loadWarnings()
        if group.keeper.id == "f4" {
            XCTAssertTrue(group.candidates.allSatisfy { checked.isAwaitingAcknowledgement($0.id) }, "every other frame differs from a keeper with an extra person")
        } else {
            XCTAssertTrue(checked.isAwaitingAcknowledgement("f4"))
            XCTAssertEqual(checked.warnings["f4"], [.differentPeople])
        }
        checked.markEverythingElseForDeletion()
        XCTAssertFalse(checked.draft.deleteIDs.contains("f4"), "Mark the rest never marks the frame with the extra person")
    }
}
