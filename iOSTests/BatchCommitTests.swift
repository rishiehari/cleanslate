import XCTest
import Photos
import CleanSlateCore
@testable import CleanSlate

@MainActor
final class BatchCommitTests: XCTestCase {
    private var library: FakePhotoLibrary!
    private var coordinator: PhotoDeletionCoordinator!
    private var tray: DeletionTray!

    override func setUp() async throws {
        library = FakePhotoLibrary()
        coordinator = PhotoDeletionCoordinator(library: library,
            networkPolicy: NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { false }), protection: StaticProtectionGate())
        tray = DeletionTray(fileURL: nil)
    }

    /// n exact pairs (keeper k<i>, copy c<i>) approved into the tray.
    private func approvePairs(_ n: Int, start: Int = 0) {
        for i in start..<(start + n) {
            library.add("k\(i)", content: "c\(i)", at: Int64(1_000 + i)); library.add("c\(i)", content: "c\(i)", at: Int64(1_000 + i))
            tray.approve(group: library.exactGroup(keeper: "k\(i)", copies: ["c\(i)"], bytes: 100), selected: ["c\(i)"], manuallyReviewed: [])
        }
    }

    func testFiftyGroupsAreOneSingleDeleteRequest() async throws {
        approvePairs(50)
        let receiptOptional = await tray.deleteAll(using: coordinator)
        let receipt = try XCTUnwrap(receiptOptional)
        XCTAssertEqual(library.deleteCalls.count, 1, "one Apple prompt for the whole tray")
        XCTAssertEqual(library.deleteCalls[0].count, 50)
        XCTAssertEqual(receipt.verifiedRemoved, 50)
        XCTAssertEqual(receipt.logicalBytesRemoved, 5_000)
        XCTAssertTrue(tray.entries.isEmpty)
        for i in 0..<50 { XCTAssertNotNil(library.assets["k\(i)"], "keepers always survive") }
    }

    func testCancellingTheSystemPromptDeletesNothingAndKeepsTheTray() async {
        approvePairs(3)
        library.deleteOutcome = .userCancelled
        let receipt = await tray.deleteAll(using: coordinator)
        XCTAssertNil(receipt)
        XCTAssertEqual(tray.entries.count, 3)
        XCTAssertNil(tray.receipt, "no receipt without a deletion")
        XCTAssertNil(tray.batchNotice, "saying no is not an error")
        XCTAssertTrue(library.assets.keys.contains("c0"))
    }

    func testOneChangedGroupBlocksTheWholeBatchAndNamesIt() async throws {
        approvePairs(40)
        library.assets["c37"]?.digests = [FakePhotoLibrary.digest("edited")]       // bytes differ now
        let receipt = await tray.deleteAll(using: coordinator)
        XCTAssertNil(receipt)
        XCTAssertTrue(library.deleteCalls.isEmpty, "not a single photo was deleted")
        XCTAssertEqual(tray.needsAttention.count, 1)
        XCTAssertEqual(tray.needsAttention["test-k37"], "These files are no longer identical")
        XCTAssertTrue(tray.batchNotice?.contains("1 group changed") == true, tray.batchNotice ?? "")
        // The user taps Delete again: the other 39 go through together.
        let secondOptional = await tray.deleteAll(using: coordinator)
        let second = try XCTUnwrap(secondOptional)
        XCTAssertEqual(second.verifiedRemoved, 39)
        XCTAssertEqual(library.deleteCalls.count, 1)
        XCTAssertEqual(tray.entries.map(\.id), ["test-k37"], "only the set-aside group remains")
    }

    func testAFavoriteAppearingAfterApprovalBlocksTheBatch() async {
        approvePairs(5)
        library.update("c2", flags: [.favorite])                          // no revision change
        let receipt = await tray.deleteAll(using: coordinator)
        XCTAssertNil(receipt)
        XCTAssertTrue(library.deleteCalls.isEmpty)
        XCTAssertEqual(tray.needsAttention["test-k2"], "One of these photos is now protected, for example a favorite or in an album")
    }

    func testAPhotoCannotBeKeptInOneGroupAndDeletedInAnother() async {
        for id in ["a", "b", "c"] { library.add(id, content: "same", at: 500) }
        tray.approve(group: library.exactGroup(keeper: "a", copies: ["b"]), selected: ["b"], manuallyReviewed: [])
        tray.approve(group: library.exactGroup(keeper: "c", copies: ["a"]), selected: ["a"], manuallyReviewed: [])   // deletes the first group's keeper
        let receipt = await tray.deleteAll(using: coordinator)
        XCTAssertNil(receipt)
        XCTAssertTrue(library.deleteCalls.isEmpty)
        XCTAssertEqual(tray.needsAttention.count, 2, "both contradicting groups are set aside")
    }

    func testGroupsAndKeeperlessItemsShareOneRequest() async throws {
        approvePairs(2)
        library.add("shot1", subtypes: 1 << 2, size: 10); library.add("shot2", subtypes: 1 << 2, size: 20)
        tray.approveStandalone(items: ["shot1", "shot2"].map { StandaloneItem(snapshot: library.assets[$0]!.snapshot, verifiedBytes: library.sizes[$0]) })
        let receiptOptional = await tray.deleteAll(using: coordinator)
        let receipt = try XCTUnwrap(receiptOptional)
        XCTAssertEqual(library.deleteCalls.count, 1)
        XCTAssertEqual(Set(library.deleteCalls[0]), ["c0", "c1", "shot1", "shot2"])
        XCTAssertEqual(receipt.verifiedRemoved, 4)
        XCTAssertTrue(tray.isEmpty)
    }

    func testProgressCountsEveryExactGroupBeforeTheSinglePrompt() async throws {
        approvePairs(6)
        var seen: [Int] = []
        let outcome = try await coordinator.commitBatch(groups: tray.readyEntries, standalone: [], progress: { done, total in
            XCTAssertEqual(total, 6); seen.append(done)
        })
        guard case .completed = outcome else { return XCTFail("expected completion") }
        XCTAssertEqual(seen, [0, 1, 2, 3, 4, 5, 6])
    }

    func testCancellingWhileRecheckingDeletesNothing() async {
        approvePairs(10)
        let task = Task { await self.tray.deleteAll(using: self.coordinator) }
        task.cancel()
        let receipt = await task.value
        XCTAssertNil(receipt)
        XCTAssertTrue(library.deleteCalls.isEmpty)
        XCTAssertEqual(tray.entries.count, 10)
    }

    func testLimitedAccessIsReportedAsUncertainNotRemoved() async throws {
        approvePairs(2)
        library.authorizationAfterDelete = .limited
        let receiptOptional = await tray.deleteAll(using: coordinator)
        let receipt = try XCTUnwrap(receiptOptional)
        XCTAssertEqual(receipt.verifiedRemoved, 0)
        XCTAssertEqual(receipt.uncertain, 2)
        XCTAssertEqual(tray.entries.count, 2, "unconfirmed entries are not silently dropped from the tray")
    }

    func testAnEmptyOrRevokedBatchDoesNothing() async {
        let emptyResult = await tray.deleteAll(using: coordinator)
        XCTAssertNil(emptyResult)
        approvePairs(1)
        library.authorization = .denied
        let deniedResult = await tray.deleteAll(using: coordinator)
        XCTAssertNil(deniedResult)
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    // MARK: Chunking beyond the batch limit

    func testALargeTrayIsSplitIntoBatchesOfAtMostFiveHundred() {
        library.add("x", subtypes: 1 << 2)
        let item = StandaloneItem(snapshot: library.assets["x"]!.snapshot, verifiedBytes: 1)
        let entries = (0..<4).map { StandaloneTrayEntry(id: "s\($0)", items: Array(repeating: item, count: 300), approvedAt: Date()) }
        let chunks = DeletionTray.chunks(groups: [], standalone: entries, limit: SafetyPolicy.maximumBatchTargets)
        XCTAssertEqual(chunks.map { $0.standalone.count }, [1, 1, 1, 1], "300 + 300 would exceed 500, so each gets its own prompt")
        XCTAssertTrue(chunks.allSatisfy { $0.standalone.reduce(0) { $0 + $1.items.count } <= 500 })
    }

    func testApprovingMoreThanFiveHundredItemsCreatesSeveralEntriesAndOnePromptEach() async throws {
        for i in 0..<1_050 { library.add("s\(i)", at: Int64(i), subtypes: 1 << 2, size: 1) }
        let items = (0..<1_050).map { StandaloneItem(snapshot: library.assets["s\($0)"]!.snapshot, verifiedBytes: 1) }
        tray.approveStandalone(items: items)
        XCTAssertEqual(tray.standaloneEntries.map(\.items.count), [500, 500, 50])
        XCTAssertEqual(tray.promptCount, 3)
        let receiptOptional = await tray.deleteAll(using: coordinator)
        let receipt = try XCTUnwrap(receiptOptional)
        XCTAssertEqual(library.deleteCalls.map(\.count), [500, 500, 50], "three requests, each within the limit")
        XCTAssertEqual(receipt.verifiedRemoved, 1_050)
    }

    func testUndoRemovesAllEntriesAddedByOneBigApproval() {
        for i in 0..<700 { library.add("u\(i)", at: Int64(i), subtypes: 1 << 2) }
        tray.approveStandalone(items: (0..<700).map { StandaloneItem(snapshot: library.assets["u\($0)"]!.snapshot, verifiedBytes: nil) })
        XCTAssertEqual(tray.standaloneEntries.count, 2)
        tray.undo()
        XCTAssertTrue(tray.standaloneEntries.isEmpty)
    }
}
