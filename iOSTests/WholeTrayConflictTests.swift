import XCTest
import Photos
import CleanSlateCore
import UIKit
@testable import CleanSlate

/// Whole-tray consistency before chunking (validator finding B-1, 2026-11-12): the batch policy only sees
/// one chunk of ≤500 targets, so without this a photo KEPT by an entry in chunk 1 could be deleted as a
/// TARGET by an entry in chunk 2.
@MainActor
final class WholeTrayConflictTests: XCTestCase {
    private var library: FakePhotoLibrary!
    private var coordinator: PhotoDeletionCoordinator!
    private var tray: DeletionTray!

    override func setUp() async throws {
        library = FakePhotoLibrary()
        coordinator = PhotoDeletionCoordinator(library: library,
            networkPolicy: NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { false }), protection: StaticProtectionGate())
        tray = DeletionTray(fileURL: nil)
    }

    private func filler(_ i: Int) -> PhotoReviewGroup {
        library.add("fk\(i)", content: "fc\(i)", at: Int64(5_000 + i)); library.add("fc\(i)", content: "fc\(i)", at: Int64(5_000 + i))
        return library.exactGroup(keeper: "fk\(i)", copies: ["fc\(i)"], bytes: 100)
    }

    func testKeeperInFirstChunkIsNeverDeletedAsTargetInLaterChunk() async {
        library.add("P", content: "same", at: 1); library.add("c1", content: "same", at: 2); library.add("Q", content: "same", at: 3)
        tray.approve(group: library.exactGroup(keeper: "P", copies: ["c1"], bytes: 100), selected: ["c1"], manuallyReviewed: [])
        for i in 0..<499 { tray.approve(group: filler(i), selected: ["fc\(i)"], manuallyReviewed: []) }
        tray.approve(group: library.exactGroup(keeper: "Q", copies: ["P"], bytes: 100), selected: ["P"], manuallyReviewed: [])
        XCTAssertEqual(tray.promptCount, 2, "precondition: the two conflicting entries land in different chunks")
        let receipt = await tray.deleteAll(using: coordinator)
        XCTAssertNotNil(library.assets["P"], "P is kept by one group and must not be deleted by another")
        XCTAssertNil(receipt)
        XCTAssertTrue(library.deleteCalls.isEmpty, "nothing is deleted when the tray is inconsistent")
        XCTAssertEqual(tray.needsAttention.count, 2, "both conflicting entries are set aside")
        XCTAssertTrue(tray.needsAttention.values.allSatisfy { $0 == DeletionTray.overlapAcrossTrayReason })
        XCTAssertEqual(tray.batchNotice, "2 items need another look and were set aside. Nothing was deleted. Tap Delete again to remove the rest.")
    }

    func testAfterSettingAsideTheRestDeletesAndTheKeeperSurvives() async {
        library.add("P", content: "same", at: 1); library.add("c1", content: "same", at: 2); library.add("Q", content: "same", at: 3)
        tray.approve(group: library.exactGroup(keeper: "P", copies: ["c1"], bytes: 100), selected: ["c1"], manuallyReviewed: [])
        for i in 0..<499 { tray.approve(group: filler(i), selected: ["fc\(i)"], manuallyReviewed: []) }
        tray.approve(group: library.exactGroup(keeper: "Q", copies: ["P"], bytes: 100), selected: ["P"], manuallyReviewed: [])
        _ = await tray.deleteAll(using: coordinator)
        _ = await tray.deleteAll(using: coordinator)        // second tap: only the 499 consistent entries
        XCTAssertNotNil(library.assets["P"]); XCTAssertNotNil(library.assets["Q"]); XCTAssertNotNil(library.assets["c1"])
        XCTAssertEqual(library.deleteCalls.flatMap { $0 }.count, 499)
        XCTAssertFalse(library.deleteCalls.flatMap { $0 }.contains("P"))
    }

    func testSingleOversizeGroupIsSetAsideWithAnHonestReason() async {
        library.add("K", content: "big", at: 1)
        var copies: [String] = []
        for i in 0..<501 { library.add("x\(i)", content: "big", at: Int64(10 + i)); copies.append("x\(i)") }
        tray.approve(group: library.exactGroup(keeper: "K", copies: copies, bytes: 10), selected: Set(copies), manuallyReviewed: [])
        let receipt = await tray.deleteAll(using: coordinator)
        XCTAssertNil(receipt)
        XCTAssertTrue(library.deleteCalls.isEmpty)
        XCTAssertEqual(tray.needsAttention.values.first, DeletionTray.tooLargeReason)
    }

    // MARK: pure helper

    private func entry(_ id: String, keep: String, delete: Set<String>) -> TrayEntry {
        for photo in delete.union([keep]) where library.assets[photo] == nil { library.add(photo, content: "z", at: 1) }
        tray.approve(group: library.exactGroup(keeper: keep, copies: Array(delete).sorted(), bytes: 1), selected: delete, manuallyReviewed: [])
        return tray.entries.last!
    }

    func testSameKeeperInSeveralEntriesIsAllowed() {
        for photo in ["A", "B", "K", "a1", "b1"] { library.add(photo, content: "z", at: 1) }
        tray.approve(group: library.exactGroup(keeper: "A", copies: ["a1", "K"], bytes: 1), selected: ["a1"], manuallyReviewed: [], keepers: ["A", "K"])
        tray.approve(group: library.exactGroup(keeper: "B", copies: ["b1", "K"], bytes: 1), selected: ["b1"], manuallyReviewed: [], keepers: ["B", "K"])
        XCTAssertEqual(tray.entries.count, 2)
        XCTAssertTrue(DeletionTray.wholeTrayConflicts(groups: tray.entries, standalone: [], limit: 500).isEmpty)
    }

    func testKeptInOneEntryDeletedInAnotherConflicts() {
        for photo in ["A", "B", "K", "a1"] { library.add(photo, content: "z", at: 1) }
        tray.approve(group: library.exactGroup(keeper: "A", copies: ["a1", "K"], bytes: 1), selected: ["a1"], manuallyReviewed: [], keepers: ["A", "K"])
        tray.approve(group: library.exactGroup(keeper: "B", copies: ["K"], bytes: 1), selected: ["K"], manuallyReviewed: [])
        XCTAssertEqual(DeletionTray.wholeTrayConflicts(groups: tray.entries, standalone: [], limit: 500).count, 2)
    }

    func testSameTargetInTwoEntriesConflicts() {
        let a = entry("a", keep: "K1", delete: ["T"]), b = entry("b", keep: "K2", delete: ["T"])
        XCTAssertEqual(Set(DeletionTray.wholeTrayConflicts(groups: [a, b], standalone: [], limit: 500).keys), [a.id, b.id])
    }

    func testDisjointEntriesNeverConflict() {
        let a = entry("a", keep: "K1", delete: ["a1"]), b = entry("b", keep: "K2", delete: ["b1"])
        XCTAssertTrue(DeletionTray.wholeTrayConflicts(groups: [a, b], standalone: [], limit: 1).isEmpty)
    }

    // MARK: validator round (main) — B1 / m1 / m2

    func testSetAsideEntrysKeeperIsNeverDeletedByAReadyEntry() async {
        library.add("P", content: "same", at: 1); library.add("c1", content: "same", at: 2); library.add("Q", content: "same", at: 3)
        tray.approve(group: library.exactGroup(keeper: "P", copies: ["c1"], bytes: 100), selected: ["c1"], manuallyReviewed: [])
        let stalled = tray.entries[0].id
        tray.setNeedsAttention([stalled: "A photo changed since you approved it"])
        tray.approve(group: library.exactGroup(keeper: "Q", copies: ["P"], bytes: 100), selected: ["P"], manuallyReviewed: [])
        let ready = tray.entries[1].id
        let receipt = await tray.deleteAll(using: coordinator)
        XCTAssertNil(receipt)
        XCTAssertNotNil(library.assets["P"], "P is kept by a set-aside entry; a ready entry must not delete it")
        XCTAssertTrue(library.deleteCalls.isEmpty)
        XCTAssertEqual(tray.needsAttention[ready], DeletionTray.overlapAcrossTrayReason)
        XCTAssertEqual(tray.needsAttention[stalled], "A photo changed since you approved it", "an existing reason is not overwritten")
        XCTAssertEqual(tray.batchNotice, "1 item needs another look and was set aside. Nothing was deleted.")
    }

    func testSecondTapWithNothingReadySaysSo() async {
        library.add("K", content: "z", at: 1); library.add("c", content: "z", at: 2)
        tray.approve(group: library.exactGroup(keeper: "K", copies: ["c"], bytes: 1), selected: ["c"], manuallyReviewed: [])
        tray.setNeedsAttention([tray.entries[0].id: "x"])
        let receipt = await tray.deleteAll(using: coordinator)
        XCTAssertNil(receipt)
        XCTAssertEqual(tray.batchNotice, "Nothing is ready to delete. Items that need another look stay in your tray.")
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testRawCancellationDuringRecheckIsAStopNotAChange() async {
        for i in 0..<5 {
            library.add("k\(i)", content: "c\(i)", at: Int64(1_000 + i)); library.add("c\(i)", content: "c\(i)", at: Int64(1_000 + i))
            tray.approve(group: library.exactGroup(keeper: "k\(i)", copies: ["c\(i)"], bytes: 100), selected: ["c\(i)"], manuallyReviewed: [])
        }
        let raw = RawCancellationLibrary(library)
        let stoppable = PhotoDeletionCoordinator(library: raw,
            networkPolicy: NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { false }), protection: StaticProtectionGate())
        var task: Task<DeletionReceipt?, Never>?
        raw.afterDigest = { task?.cancel() }
        task = Task { await self.tray.deleteAll(using: stoppable) }
        let receipt = await task!.value
        XCTAssertNil(receipt)
        XCTAssertTrue(library.deleteCalls.isEmpty)
        XCTAssertEqual(tray.batchNotice, "Stopped. Nothing was deleted.")
        XCTAssertTrue(tray.needsAttention.isEmpty, "a Stop must not mark groups as changed")
    }

    func testLocalThumbnailRetryOnlyForMissingDerivative() {
        XCTAssertTrue(PhotoKitLibraryClient.shouldRetryLocally(imageMissing: true, cancelled: false, inCloud: false))
        XCTAssertFalse(PhotoKitLibraryClient.shouldRetryLocally(imageMissing: false, cancelled: false, inCloud: false))
        XCTAssertFalse(PhotoKitLibraryClient.shouldRetryLocally(imageMissing: true, cancelled: true, inCloud: false))
        XCTAssertFalse(PhotoKitLibraryClient.shouldRetryLocally(imageMissing: true, cancelled: false, inCloud: true), "never reaches for iCloud")
    }
}

/// Forwards to the fake but throws a RAW CancellationError from digests once the task is cancelled
/// (what PhotoKitLibraryClient does via Task.checkCancellation).
private final class RawCancellationLibrary: PhotoLibraryClient {
    let inner: FakePhotoLibrary
    var afterDigest: (() -> Void)?
    init(_ inner: FakePhotoLibrary) { self.inner = inner }
    var authorization: PHAuthorizationStatus { inner.authorization }
    func requestAccess() async -> PHAuthorizationStatus { await inner.requestAccess() }
    func inventoryPage(offset: Int, limit: Int) -> (photos: [PhotoSnapshot], total: Int) { inner.inventoryPage(offset: offset, limit: limit) }
    func activitySummary() async throws -> PhotoActivitySummary { try await inner.activitySummary() }
    func scanInventoryPage(offset: Int, limit: Int, request: ScanInventoryRequest) async throws -> ScanInventoryPage {
        try await inner.scanInventoryPage(offset: offset, limit: limit, request: request)
    }
    func currentChangeToken() -> Data? { inner.currentChangeToken() }
    func changes(since token: Data) -> LibraryChangeResult { inner.changes(since: token) }
    func snapshot(id: String, inspectAlbums: Bool) -> PhotoSnapshot? { inner.snapshot(id: id, inspectAlbums: inspectAlbums) }
    func thumbnail(_ id: String, target: CGFloat) async -> UIImage? { await inner.thumbnail(id, target: target) }
    func digests(id: String, allowNetwork: Bool) async throws -> [ResourceDigest] {
        let result = try await inner.digests(id: id, allowNetwork: allowNetwork)
        afterDigest?()
        if Task.isCancelled { throw CancellationError() }
        return result
    }
    func verifiedSize(id: String) async -> Int64? { await inner.verifiedSize(id: id) }
    func userAlbumAssetIDs() -> Set<String> { inner.userAlbumAssetIDs() }
    func albumMemberIDs(among ids: [String]) async -> Set<String> { await inner.albumMemberIDs(among: ids) }
    func delete(ids: [String], expectedRevisions: [String: String]) async throws { try await inner.delete(ids: ids, expectedRevisions: expectedRevisions) }
    func observeChanges(_ onChange: @escaping @MainActor () -> Void) -> ChangeSubscription { inner.observeChanges(onChange) }
}
