import XCTest
import Photos
import CleanSlateCore
@testable import CleanSlate

/// N05 C4: the deletion coordinator consults the protection gate at every commit, with fresh state,
/// and fails closed. Every test here asserts that NOTHING reached `deleteAssets` (the fake's `deleteCalls`).
@MainActor
final class ProtectionCommitTests: XCTestCase {
    private var library: FakePhotoLibrary!
    private var gate: StaticProtectionGate!
    private var coordinator: PhotoDeletionCoordinator!
    private var tray: DeletionTray!
    private let screenshot: UInt = 1 << 2

    override func setUp() async throws {
        library = FakePhotoLibrary()
        gate = StaticProtectionGate()
        coordinator = PhotoDeletionCoordinator(
            library: library,
            networkPolicy: NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { false }),
            protection: gate)
        tray = DeletionTray(fileURL: nil)
    }

    typealias DeletionError = PhotoDeletionCoordinator.DeletionError

    private func expectError(_ expected: DeletionError, file: StaticString = #filePath, line: UInt = #line,
                             _ body: () async throws -> Void) async {
        do { try await body(); XCTFail("expected \(expected)", file: file, line: line) }
        catch let e as DeletionError { XCTAssertEqual(e, expected, file: file, line: line) }
        catch { XCTFail("unexpected \(error)", file: file, line: line) }
    }

    private func pair(_ i: Int = 0) -> PhotoReviewGroup {
        library.add("k\(i)", content: "c\(i)", at: Int64(1_000 + i)); library.add("c\(i)", content: "c\(i)", at: Int64(1_000 + i))
        return library.exactGroup(keeper: "k\(i)", copies: ["c\(i)"], bytes: 100)
    }
    private func approvePairs(_ n: Int) {
        for i in 0..<n { tray.approve(group: pair(i), selected: ["c\(i)"], manuallyReviewed: []) }
    }
    private func standaloneItem(_ id: String) -> StandaloneItem {
        if library.assets[id] == nil { library.add(id, subtypes: screenshot, size: 100) }
        return StandaloneItem(snapshot: library.assets[id]!.snapshot, verifiedBytes: library.sizes[id])
    }

    // MARK: Protected targets (single, standalone, batch)

    func testProtectedTargetBlocksSingleCommit() async {
        let group = pair()
        gate.protectedIDs = ["c0"]
        await expectError(.unsafe("protected")) { _ = try await coordinator.commit(group: group, selected: ["c0"], manuallyReviewed: []) }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testProtectedKeeperDoesNotBlockDeletingTheCopy() async throws {
        let group = pair()
        gate.protectedIDs = ["k0"]
        let result = try await coordinator.commit(group: group, selected: ["c0"], manuallyReviewed: [])
        XCTAssertEqual(library.deleteCalls, [["c0"]])
        XCTAssertEqual(result.verifiedRemoved, 1)
    }

    func testUnprotectedSingleCommitStillDeletes() async throws {
        let group = pair()
        _ = try await coordinator.commit(group: group, selected: ["c0"], manuallyReviewed: [])
        XCTAssertEqual(library.deleteCalls, [["c0"]])
    }

    func testProtectedScreenshotNotCommittable() async {
        let item = standaloneItem("s1")
        gate.protectedIDs = ["s1"]
        await expectError(.unsafe("protected")) { _ = try await coordinator.commitStandalone(items: [item]) }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testProtectedTargetBlocksBatchAndNamesTheRule() async throws {
        approvePairs(3)
        gate.protectedIDs = ["c1"]
        let outcome = try await coordinator.commitBatch(groups: tray.readyEntries, standalone: [])
        guard case .blocked(let reasons) = outcome else { return XCTFail("expected blocked") }
        XCTAssertEqual(reasons["test-k1"], TrayChecker.protectedByRuleReason)
        XCTAssertTrue(library.deleteCalls.isEmpty, "a batch with one protected target deletes nothing at all")
    }

    func testProtectedStandaloneItemBlocksBatch() async throws {
        approvePairs(1)
        tray.approveStandalone(items: [standaloneItem("s1"), standaloneItem("s2")])
        gate.protectedIDs = ["s2"]
        let outcome = try await coordinator.commitBatch(groups: tray.readyEntries, standalone: tray.readyStandaloneEntries)
        guard case .blocked(let reasons) = outcome else { return XCTFail("expected blocked") }
        XCTAssertEqual(reasons[tray.standaloneEntries[0].id], TrayChecker.protectedByRuleReason)
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testProtectedKeeperInBatchStillDeletes() async throws {
        approvePairs(2)
        gate.protectedIDs = ["k0"]
        let outcome = try await coordinator.commitBatch(groups: tray.readyEntries, standalone: [])
        guard case .completed(let receipt) = outcome else { return XCTFail("expected completed") }
        XCTAssertEqual(receipt.verifiedRemoved, 2)
    }

    // MARK: Fail closed when the rules cannot answer (E1, E6)

    func testUnavailableBlocksAllDeletion() async throws {
        let group = pair()
        let item = standaloneItem("s1")
        approvePairs(0)
        tray.approve(group: group, selected: ["c0"], manuallyReviewed: [])
        for state: ProtectionAvailability in [.unavailable("x"), .lost, .loading] {
            gate.availability = state
            await expectError(.protectionUnavailable) { _ = try await coordinator.commit(group: group, selected: ["c0"], manuallyReviewed: []) }
            await expectError(.protectionUnavailable) { _ = try await coordinator.commitStandalone(items: [item]) }
            await expectError(.protectionUnavailable) { _ = try await coordinator.commitBatch(groups: tray.readyEntries, standalone: []) }
        }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testProductionTrayPathReportsUnavailableAndKeepsTheTray() async {
        approvePairs(3)
        gate.availability = .unavailable("down")
        let receipt = await tray.deleteAll(using: coordinator)
        XCTAssertNil(receipt)
        XCTAssertEqual(tray.batchNotice, "Protection rules couldn't be checked. Nothing was deleted.")
        XCTAssertEqual(tray.entries.count, 3)
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testPendingWriteBlocksCommit() async {
        let group = pair()
        let item = standaloneItem("s1")
        approvePairs(0)
        tray.approve(group: group, selected: ["c0"], manuallyReviewed: [])
        gate.pendingWrites = 1
        await expectError(.protectionUnavailable) { _ = try await coordinator.commit(group: group, selected: ["c0"], manuallyReviewed: []) }
        await expectError(.protectionUnavailable) { _ = try await coordinator.commitStandalone(items: [item]) }
        await expectError(.protectionUnavailable) { _ = try await coordinator.commitBatch(groups: tray.readyEntries, standalone: []) }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    // MARK: Rules changing while a commit is running (G2, E7)

    func testRuleCreatedDuringRehashBlocksBatch() async {
        approvePairs(3)
        library.onDigests = { [gate] id in if id == "c2" { gate!.protectedIDs.insert("c2"); gate!.revision += 1 } }
        await expectError(.protectionChanged) { _ = try await coordinator.commitBatch(groups: tray.readyEntries, standalone: []) }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testRuleCreatedDuringRehashBlocksSingleCommit() async {
        let group = pair()
        library.onDigests = { [gate] id in if id == "c0" { gate!.protectedIDs.insert("c0"); gate!.revision += 1 } }
        await expectError(.protectionChanged) { _ = try await coordinator.commit(group: group, selected: ["c0"], manuallyReviewed: []) }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testRuleChangeBetweenSnapshotsAndDeleteBlocksStandalone() async {
        let item = standaloneItem("s1")
        // The gate moves while the commit is already evaluating (there is no await inside commitStandalone before delete).
        var fired = false
        gate.onVerdict = { [gate] _ in if !fired { fired = true; gate!.revision += 1 } }
        await expectError(.protectionChanged) { _ = try await coordinator.commitStandalone(items: [item]) }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testRuleRemovalDuringCommitStillBlocks() async {
        approvePairs(2)
        gate.protectedIDs = []
        library.onDigests = { [gate] _ in gate!.revision += 1 }     // a removal also moves the revision
        await expectError(.protectionChanged) { _ = try await coordinator.commitBatch(groups: tray.readyEntries, standalone: []) }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testWriteStartingDuringRehashBlocksBatch() async {
        approvePairs(2)
        library.onDigests = { [gate] _ in gate!.pendingWrites = 1 }
        await expectError(.protectionChanged) { _ = try await coordinator.commitBatch(groups: tray.readyEntries, standalone: []) }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testAvailabilityLostDuringRehashBlocksBatch() async {
        approvePairs(2)
        library.onDigests = { [gate] _ in gate!.availability = .unavailable("gone") }
        await expectError(.protectionChanged) { _ = try await coordinator.commitBatch(groups: tray.readyEntries, standalone: []) }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testProductionTrayPathReportsChangedRulesAndKeepsTheTray() async {
        approvePairs(2)
        library.onDigests = { [gate] _ in gate!.revision += 1 }
        let receipt = await tray.deleteAll(using: coordinator)
        XCTAssertNil(receipt)
        XCTAssertEqual(tray.batchNotice, "Your protection rules changed while checking. Nothing was deleted. Tap Delete again.")
        XCTAssertEqual(tray.entries.count, 2)
        XCTAssertTrue(library.deleteCalls.isEmpty)
        // Rules settled: the next tap goes through.
        library.onDigests = nil
        let second = await tray.deleteAll(using: coordinator)
        XCTAssertEqual(second?.verifiedRemoved, 2)
    }

    // MARK: Chunking and cancellation (E14, E15)

    func testProtectedTargetInLaterChunkNeverDeleted() async {
        let count = SafetyPolicy.maximumBatchTargets + 20
        let items = (0..<count).map { standaloneItem("s\($0)") }
        tray.approveStandalone(items: items)
        XCTAssertEqual(tray.standaloneEntries.count, 2)
        // Protection arrives while the FIRST chunk's delete is in flight; the second chunk holds the protected photo.
        let protectedID = items[count - 1].id
        library.beforeDelete = { [gate] in gate!.protectedIDs.insert(protectedID); gate!.revision += 1 }
        _ = await tray.deleteAll(using: coordinator)
        XCTAssertEqual(library.deleteCalls.count, 1, "only the first chunk was sent")
        XCTAssertFalse(library.deleteCalls.joined().contains(protectedID))
        XCTAssertNotNil(library.assets[protectedID])
    }

    func testCancelDuringRehashWithPendingRuleDeletesNothing() async {
        approvePairs(10)
        var task: Task<DeletionReceipt?, Never>?
        library.onDigests = { [gate] _ in gate!.pendingWrites = 1; task?.cancel() }
        task = Task { await self.tray.deleteAll(using: self.coordinator) }
        let receipt = await task!.value
        XCTAssertNil(receipt)
        XCTAssertTrue(library.deleteCalls.isEmpty)
        XCTAssertEqual(tray.entries.count, 10)
    }

    // MARK: Messages

    func testErrorMessagesAreTheAgreedPlainWords() {
        XCTAssertEqual(DeletionError.protectionUnavailable.errorDescription, "Protection rules couldn't be checked. Nothing was deleted.")
        XCTAssertEqual(DeletionError.protectionChanged.errorDescription,
                       "Your protection rules changed while checking. Nothing was deleted. Tap Delete again.")
        XCTAssertEqual(TrayChecker.protectedByRuleReason, "Protected by your rule — always kept")
    }
}
