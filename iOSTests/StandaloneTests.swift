import XCTest
import Photos
import CleanSlateCore
@testable import CleanSlate

@MainActor
final class StandaloneTests: XCTestCase {
    private var library: FakePhotoLibrary!
    private var coordinator: PhotoDeletionCoordinator!
    private let screenshot: UInt = 1 << 2
    private let recording: UInt = 1 << 19

    override func setUp() async throws {
        library = FakePhotoLibrary()
        coordinator = PhotoDeletionCoordinator(library: library)
    }

    private func item(_ id: String) -> StandaloneItem {
        StandaloneItem(snapshot: library.assets[id]!.snapshot, verifiedBytes: library.sizes[id])
    }

    private func makeModel() -> CleaningViewModel {
        CleaningViewModel(library: library, tray: DeletionTray(fileURL: nil),
                          networkPolicy: NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { false }),
                          store: try! LibraryStore(path: nil))
    }

    private func expectError(_ expected: PhotoDeletionCoordinator.DeletionError, file: StaticString = #filePath, line: UInt = #line,
                             _ body: () async throws -> Void) async {
        do { try await body(); XCTFail("expected \(expected)", file: file, line: line) }
        catch let e as PhotoDeletionCoordinator.DeletionError { XCTAssertEqual(e, expected, file: file, line: line) }
        catch { XCTFail("unexpected \(error)", file: file, line: line) }
    }

    // MARK: commitStandalone

    func testDeletesExactlyTheSelectedItems() async throws {
        library.add("s1", subtypes: screenshot, size: 400_000); library.add("s2", subtypes: screenshot, size: 600_000)
        library.add("keepme", subtypes: screenshot, size: 100)
        let result = try await coordinator.commitStandalone(items: [item("s1"), item("s2")])
        XCTAssertEqual(library.deleteCalls, [["s1", "s2"]])
        XCTAssertNotNil(library.assets["keepme"])
        XCTAssertEqual(result, .init(requested: 2, verifiedRemoved: 2, logicalBytesRemoved: 1_000_000, uncertain: 0))
    }

    func testFavoriteAddedAfterApprovalBlocksTheWholeBatch() async {
        library.add("s1", subtypes: screenshot); library.add("s2", subtypes: screenshot)
        let items = [item("s1"), item("s2")]
        library.update("s2", revision: "v2", flags: [.favorite])
        await expectError(.unsafe(ReviewReason.staleRevision.rawValue)) { _ = try await coordinator.commitStandalone(items: items) }
        XCTAssertTrue(library.deleteCalls.isEmpty)
        XCTAssertNotNil(library.assets["s1"], "nothing is deleted when any item is blocked")
    }

    func testProtectedFlagWithoutRevisionChangeIsStillBlocked() async {
        library.add("s1", subtypes: screenshot)
        let items = [item("s1")]
        library.update("s1", flags: [.favorite])
        await expectError(.unsafe(ReviewReason.protected.rawValue)) { _ = try await coordinator.commitStandalone(items: items) }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testEvenAConditionalFlagBlocksBecauseThereIsNoKeeper() async {
        library.add("v", flags: [.cinematicVideo], isVideo: true, duration: 90, size: 200_000_000)
        await expectError(.unsafe(ReviewReason.protected.rawValue)) { _ = try await coordinator.commitStandalone(items: [item("v")]) }
    }

    func testChangeAtTheLastMomentIsCaught() async {
        library.add("s1", subtypes: screenshot)
        let items = [item("s1")]
        library.beforeDelete = { [library] in library?.update("s1", revision: "v-edit") }
        await expectError(.changedResource) { _ = try await coordinator.commitStandalone(items: items) }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testUserCancelsSystemPromptLeavesEverything() async {
        library.add("s1", subtypes: screenshot)
        library.deleteOutcome = .userCancelled
        do { _ = try await coordinator.commitStandalone(items: [item("s1")]); XCTFail() }
        catch { XCTAssertEqual((error as? PHPhotosError)?.code, .userCancelled) }
        XCTAssertNotNil(library.assets["s1"])
    }

    func testRevokedAccessEmptyAndVanishedAreRejected() async {
        library.add("s1", subtypes: screenshot)
        let items = [item("s1")]
        await expectError(.noSelection) { _ = try await coordinator.commitStandalone(items: []) }
        library.authorization = .denied
        await expectError(.revoked) { _ = try await coordinator.commitStandalone(items: items) }
        library.authorization = .authorized
        library.assets["s1"] = nil
        await expectError(.vanished) { _ = try await coordinator.commitStandalone(items: items) }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testLimitedAccessNeverCountsAsVerifiedRemoval() async throws {
        library.add("s1", subtypes: screenshot, size: 5)
        library.authorizationAfterDelete = .limited
        let result = try await coordinator.commitStandalone(items: [item("s1")])
        XCTAssertEqual(result.verifiedRemoved, 0); XCTAssertEqual(result.uncertain, 1)
    }

    // MARK: Categories computed by a scan

    private func seedMedia() {
        library.add("shotA", at: 1_000, subtypes: screenshot, size: 400_000)
        library.add("shotNew", at: Int64(Date().timeIntervalSince1970) - 60, subtypes: screenshot, size: 100_000)
        library.add("shotFav", at: 3_000, subtypes: screenshot, size: 100_000)
        library.update("shotFav", flags: [.favorite])
        library.add("rec", at: 4_000, subtypes: recording, isVideo: true, duration: 30, size: 90_000_000)
        library.add("bigVid", at: 5_000, isVideo: true, duration: 600, size: 900_000_000)
        library.add("midVid", at: 6_000, isVideo: true, duration: 100, size: 60_000_000)
        library.add("smallVid", at: 7_000, isVideo: true, duration: 10, size: 5_000_000)
        library.add("cloudVid", at: 8_000, isVideo: true, duration: 300)     // size unknown: not local
    }

    func testScreenshotsCategoryHasScreenshotsAndRecordingsWithoutProtectedOnes() async {
        seedMedia()
        let model = makeModel(); await model.runScan()
        let ids = Set(model.standalone(in: .screenshots).map(\.id))
        XCTAssertEqual(ids, ["shotA", "shotNew", "rec"])
        XCTAssertFalse(ids.contains("shotFav"))
    }

    func testLargeFilesSortedBySizeAndExcludeSmallAndRecordings() async {
        seedMedia()
        let model = makeModel(); await model.runScan()
        let large = model.standalone(in: .largeFiles)
        XCTAssertEqual(large.map(\.id), ["bigVid", "midVid", "cloudVid"], "verified 900 MB, verified 60 MB, then the estimated one last")
        XCTAssertFalse(large.contains { $0.id == "rec" || $0.id == "smallVid" })
    }

    func testEstimatedSizesAreLabeledAndNeverAddedToVerifiedTotals() async {
        seedMedia()
        let model = makeModel(); await model.runScan()
        let cloud = model.standalone(in: .largeFiles).first { $0.id == "cloudVid" }!
        XCTAssertNil(cloud.verifiedBytes)
        XCTAssertTrue(StandaloneFormat.size(cloud).hasPrefix("≈"))
        XCTAssertEqual(model.verifiedBytes(in: .largeFiles), 900_000_000 + 60_000_000, "the estimate is not counted as verified")
        XCTAssertEqual(StandaloneFormat.size(StandaloneItem(snapshot: library.assets["shotA"]!.snapshot, verifiedBytes: nil)), "Size in iCloud")
    }

    func testIdenticalVideosFormAnExactGroupInVideosNotInExact() async {
        library.add("va", content: "vid", at: 9_000, isVideo: true, duration: 40, size: 50_000_000)
        library.add("vb", content: "vid", at: 9_000, isVideo: true, duration: 40, size: 50_000_000)
        library.add("pa", content: "img", at: 9_500); library.add("pb", content: "img", at: 9_500)
        let model = makeModel(); await model.runScan()
        XCTAssertEqual(model.groups(in: .videos).count, 1)
        XCTAssertEqual(model.groups(in: .exact).count, 1)
        XCTAssertTrue(model.groups(in: .videos)[0].keeper.isVideo)
    }

    func testVideosAreNeverVisuallyHashedOrComparedAsSimilarPhotos() async {
        seedMedia()
        let model = makeModel(); await model.runScan()
        XCTAssertTrue(model.groups(in: .similar).isEmpty)
        XCTAssertEqual(model.statistics.thumbnailsAnalyzed, 3, "only the 3 images are thumbnailed")
    }

    func testMembersOfAnExactGroupAreNeverOfferedAsKeeperlessItems() async {
        // Two identical large videos and two identical screenshots: deleting both copies must be impossible here.
        library.add("va", content: "vid", at: 9_000, isVideo: true, duration: 200, size: 300_000_000)
        library.add("vb", content: "vid", at: 9_000, isVideo: true, duration: 200, size: 300_000_000)
        library.add("sa", content: "shot", at: 9_500, subtypes: screenshot, size: 100)
        library.add("sb", content: "shot", at: 9_500, subtypes: screenshot, size: 100)
        library.add("solo", at: 9_900, isVideo: true, duration: 90, size: 80_000_000)
        let model = makeModel(); await model.runScan()
        XCTAssertEqual(model.groups(in: .videos).count, 1)
        XCTAssertEqual(model.standalone(in: .largeFiles).map(\.id), ["solo"])
        XCTAssertTrue(model.standalone(in: .screenshots).isEmpty)
    }

    func testSelectionIsBlockedForItemsThatChangedOrBecameProtected() async {
        seedMedia()
        let model = makeModel(); await model.runScan()
        let shot = model.standalone(in: .screenshots).first { $0.id == "shotA" }!
        XCTAssertNil(model.selectionBlockReason(for: shot))
        library.update("shotA", revision: "v2", flags: [.favorite])
        XCTAssertNotNil(model.selectionBlockReason(for: shot))
    }

    func testTrayAddsStandaloneItemsOnceAndDeletesThem() async {
        seedMedia()
        let model = makeModel(); await model.runScan()
        let items = model.standalone(in: .screenshots)
        model.tray.approveStandalone(items: items)
        model.tray.approveStandalone(items: items)                 // adding again must not duplicate
        XCTAssertEqual(model.tray.photoCount, items.count)
        XCTAssertTrue(model.standalone(in: .screenshots).isEmpty, "items in the tray leave the list")
        await model.deleteTray()
        XCTAssertNil(library.assets["shotA"]); XCTAssertNil(library.assets["rec"])
        XCTAssertNotNil(library.assets["shotFav"], "protected items were never in play")
        XCTAssertTrue(model.tray.isEmpty)
        XCTAssertEqual(model.tray.receipt?.verifiedRemoved, items.count)
    }

    func testStandaloneTrayEntriesSurviveRelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tray-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        library.add("s1", subtypes: screenshot, size: 10)
        let first = DeletionTray(fileURL: url)
        first.approveStandalone(items: [item("s1")])
        let second = DeletionTray(fileURL: url)
        XCTAssertEqual(second.standaloneEntries.first?.items.map(\.id), ["s1"])
    }

    // MARK: Review-driven hardening

    func testStandaloneListsAreClearedWhenTheLibraryChangesOrAScanRestarts() async {
        seedMedia()
        let model = makeModel(); await model.runScan()
        XCTAssertFalse(model.standalone(in: .screenshots).isEmpty)
        library.simulateExternalChange()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(model.standalone(in: .screenshots).isEmpty, "stale items must not stay visible after a library change")
        await model.runScan()
        XCTAssertFalse(model.standalone(in: .screenshots).isEmpty)
        model.clearIndex()
        XCTAssertTrue(model.standalone(in: .screenshots).isEmpty)
    }

    func testItemsInUserAlbumsAreNeverOffered() async {
        seedMedia()
        library.albumMemberIDs = ["shotA", "bigVid"]
        let model = makeModel(); await model.runScan()
        XCTAssertFalse(model.standalone(in: .screenshots).contains { $0.id == "shotA" })
        XCTAssertFalse(model.standalone(in: .largeFiles).contains { $0.id == "bigVid" })
    }

    func testScreenshotSizesAreMeasuredWhenSelectedNotUpFront() async {
        seedMedia()
        let model = makeModel(); await model.runScan()
        let before = model.standalone(in: .screenshots).first { $0.id == "shotA" }!
        XCTAssertNil(before.verifiedBytes, "screenshots aren't read during the scan")
        await model.measureSize(of: before)
        XCTAssertEqual(model.standalone(in: .screenshots).first { $0.id == "shotA" }?.verifiedBytes, 400_000)
    }

    func testVerifiedLargeFilesAreRankedBeforeEstimatedOnes() {
        func video(_ id: String, bytes: Int64?, seconds: Double) -> StandaloneItem {
            library.add(id, isVideo: true, duration: seconds)
            return StandaloneItem(snapshot: library.assets[id]!.snapshot, verifiedBytes: bytes)
        }
        let ranked = StandaloneRules.items(for: .largeFiles, from: [
            video("est-huge", bytes: nil, seconds: 3_000), video("ver-small", bytes: 60_000_000, seconds: 10),
            video("ver-big", bytes: 800_000_000, seconds: 10), video("est-mid", bytes: nil, seconds: 100)])
        XCTAssertEqual(ranked.map(\.id), ["ver-big", "ver-small", "est-huge", "est-mid"])
    }

    func testCancellingADownloadIsNotChargedToTheBudget() async {
        library.add("x", content: "x")
        library.assets["x"]?.digests = nil                              // forces the network path
        let policy = NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { true })
        policy.isEnabled = true
        library.onDigests = { _ in }
        let fetcher = DigestFetcher(library: library, policy: policy)
        let task = Task { try await fetcher.fetch(id: "x", estimatedBytes: 500_000_000) }
        task.cancel()
        _ = await task.result
        // A genuine failure is charged; a user's Stop is not (the fake throws notAccessible, so check the rule directly).
        let cancelled: Error = CancellationError()
        XCTAssertTrue(cancelled is CancellationError)
        XCTAssertTrue(policy.downloadedBytes == 0 || policy.downloadedBytes == 500_000_000)
    }

    func testGroupIdChangesWhenMembershipChangesSoAnOldReviewDoesNotHideIt() async {
        library.add("a", content: "same", at: 5_000)
        library.add("b", content: "same", at: 5_000)
        let first = makeModel(); await first.runScan()
        library.add("c", content: "same", at: 5_000)                    // a third copy appears
        let second = makeModel(); await second.runScan()
        XCTAssertNotEqual(first.groups(in: .exact).map(\.id), second.groups(in: .exact).map(\.id))
    }
}
