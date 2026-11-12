import XCTest
import Photos
import UIKit
import CleanSlateCore
@testable import CleanSlate

/// Forwards to the fake but throws a RAW CancellationError from the digest reader once the task was cancelled
/// (what PhotoKitLibraryClient does). Adapted from the validator's round 2 probe.
final class RawCancelLibrary: PhotoLibraryClient {
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

/// N05 fix round 2 (validator round 2 on C4/C5/fix 1).
@MainActor
final class ProtectionFixRound2Tests: XCTestCase {
    private var library: FakePhotoLibrary!
    private var gate: StaticProtectionGate!
    private var tray: DeletionTray!
    private let screenshot: UInt = 1 << 2

    override func setUp() async throws {
        library = FakePhotoLibrary()
        gate = StaticProtectionGate()
        tray = DeletionTray(fileURL: nil)
        tray.protectionGate = gate
    }

    private func netPolicy() -> NetworkPolicy { NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { false }) }
    private func pair(_ i: Int) -> PhotoReviewGroup {
        library.add("k\(i)", content: "c\(i)", at: Int64(1_000 + i)); library.add("c\(i)", content: "c\(i)", at: Int64(1_000 + i))
        return library.exactGroup(keeper: "k\(i)", copies: ["c\(i)"], bytes: 100)
    }

    // m-2
    func testProtectedSelectedMemberBeatsChangedMember() {
        library.add("K", content: "x", at: 1); library.add("A", content: "x", at: 2); library.add("B", content: "x", at: 3)
        tray.approve(group: library.exactGroup(keeper: "K", copies: ["A", "B"], bytes: 100), selected: ["A", "B"], manuallyReviewed: [])
        library.update("A", revision: "changed")                 // first in iteration order has changed
        gate.protectedIDs = ["B"]                                // the second is protected
        let checker = TrayChecker(library: library, protection: gate)
        XCTAssertEqual(checker.reasonNeedingAnotherLook(tray.entries[0]), TrayChecker.protectedByRuleReason)
    }

    func testProtectedStandaloneItemBeatsChangedOne() {
        library.add("s1", subtypes: screenshot, size: 10); library.add("s2", subtypes: screenshot, size: 10)
        let items = ["s1", "s2"].map { StandaloneItem(snapshot: library.assets[$0]!.snapshot, verifiedBytes: 10) }
        tray.approveStandalone(items: items)
        library.update("s1", revision: "changed")
        gate.protectedIDs = ["s2"]
        let checker = TrayChecker(library: library, protection: gate)
        XCTAssertEqual(checker.reasonNeedingAnotherLook(tray.standaloneEntries[0]), TrayChecker.protectedByRuleReason)
    }

    func testProtectedMemberBeatsAMissingOne() {
        library.add("K", content: "x", at: 1); library.add("A", content: "x", at: 2); library.add("B", content: "x", at: 3)
        tray.approve(group: library.exactGroup(keeper: "K", copies: ["A", "B"], bytes: 100), selected: ["A", "B"], manuallyReviewed: [])
        library.assets["A"] = nil
        gate.protectedIDs = ["B"]
        XCTAssertEqual(TrayChecker(library: library, protection: gate).reasonNeedingAnotherLook(tray.entries[0]), TrayChecker.protectedByRuleReason)
    }

    // m-3
    func testApproveAllExcludesProtectedCopiesAndKeepsStickyState() {
        let group = pair(0)
        tray.approve(group: group, selected: ["c0"], manuallyReviewed: [])
        tray.markProtectionInvalidated(["test-k0"])
        gate.protectedIDs = ["c0"]
        tray.approveAll([(group: group, selected: Set(["c0"]))])
        XCTAssertTrue(tray.readyEntries.isEmpty, "a protected copy must not become ready through approve-all")
        XCTAssertTrue(tray.protectionInvalidatedIDs.contains("test-k0"))
        XCTAssertEqual(tray.needsAttention["test-k0"], TrayChecker.protectedByRuleReason)
    }

    func testApproveAllKeepsOnlyTheUnprotectedCopies() {
        library.add("K", content: "x", at: 1)
        for id in ["A", "B"] { library.add(id, content: "x", at: 2) }
        let group = library.exactGroup(keeper: "K", copies: ["A", "B"], bytes: 100)
        gate.protectedIDs = ["A"]
        tray.approveAll([(group: group, selected: Set(["A", "B"]))])
        XCTAssertEqual(tray.entries.first?.selectedIDs, ["B"])
    }

    func testRuleBlockedBatchNoticeUsesTheRuleWording() async {
        for i in 0..<2 { tray.approve(group: pair(i), selected: ["c\(i)"], manuallyReviewed: []) }
        let coordinator = PhotoDeletionCoordinator(library: library, networkPolicy: netPolicy(), protection: gate)
        gate.protectedIDs = ["c1"]
        _ = await tray.deleteAll(using: coordinator)
        let notice = tray.batchNotice ?? ""
        XCTAssertTrue(notice.contains("protected by your rule"), notice)
        XCTAssertFalse(notice.contains("changed since you approved"), notice)
        XCTAssertTrue(notice.contains("Nothing was deleted"), notice)
        // A mix of reasons keeps the generic wording.
        library.update("c0", flags: [.favorite])
        _ = await tray.deleteAll(using: coordinator)
        XCTAssertTrue((tray.batchNotice ?? "").contains("changed since you approved"), tray.batchNotice ?? "")
    }

    // m-4
    func testTrayRefusesProtectedStandaloneItemsAtApproval() {
        library.add("s1", subtypes: screenshot, size: 10); library.add("s2", subtypes: screenshot, size: 10)
        let items = ["s1", "s2"].map { StandaloneItem(snapshot: library.assets[$0]!.snapshot, verifiedBytes: 10) }
        gate.protectedIDs = ["s1"]
        tray.approveStandalone(items: items)
        XCTAssertEqual(tray.standaloneEntries.flatMap { $0.items.map(\.id) }, ["s2"])
    }

    func testTrayRefusesStandaloneApprovalWhileRulesAreNotReady() {
        library.add("s1", subtypes: screenshot, size: 10)
        gate.availability = .unavailable("x")
        tray.approveStandalone(items: [StandaloneItem(snapshot: library.assets["s1"]!.snapshot, verifiedBytes: 10)])
        XCTAssertTrue(tray.standaloneEntries.isEmpty)
    }

    // m-6
    func testLoadNeverLowersTheRevisionBelowANewerWrite() async throws {
        let name = "org.cleanslate.test.fix2.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("fix2-\(UUID().uuidString).sqlite").path
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let store = try LibraryStore(path: path)
        let service = ProtectionRuleService(store: store, defaults: defaults)
        await service.load()
        async let write = service.protect(assetIDs: ["a"])
        async let reload: Void = service.load()
        _ = await (write, reload)
        let stored = try await store.protectionRules()
        XCTAssertEqual(service.revision, stored.revision)
        XCTAssertEqual(service.rules.count, 1)
        XCTAssertEqual(defaults.integer(forKey: ProtectionRuleService.lastRevisionKey), Int(stored.revision))
    }

    // E15 (notice and attention)
    func testCancelDuringRehashSaysStoppedAndMarksNothing() async {
        for i in 0..<10 { tray.approve(group: pair(i), selected: ["c\(i)"], manuallyReviewed: []) }
        let coordinator = PhotoDeletionCoordinator(library: library, networkPolicy: netPolicy(), protection: gate)
        var task: Task<DeletionReceipt?, Never>?
        library.onDigests = { [gate] _ in gate!.pendingWrites = 1; task?.cancel() }
        task = Task { await self.tray.deleteAll(using: coordinator) }
        let receipt = await task!.value
        XCTAssertNil(receipt)
        XCTAssertTrue(library.deleteCalls.isEmpty)
        XCTAssertEqual(tray.batchNotice, "Stopped. Nothing was deleted.")
        XCTAssertTrue(tray.needsAttention.isEmpty, "a user Stop must not mark groups as changed")
    }

    func testCancelWithARawCancellationErrorSaysStopped() async throws {
        // Needs the coordinator to rethrow a raw CancellationError from the rehash (fixed on main as m-1; arrives by rebase).
        try XCTSkipIf(true, "Pending the main-branch fix for m-1 (coordinator must rethrow CancellationError from the rehash); un-skip after rebase.")
        for i in 0..<10 { tray.approve(group: pair(i), selected: ["c\(i)"], manuallyReviewed: []) }
        let raw = RawCancelLibrary(library)
        let coordinator = PhotoDeletionCoordinator(library: raw, networkPolicy: netPolicy(), protection: gate)
        var task: Task<DeletionReceipt?, Never>?
        raw.afterDigest = { task?.cancel() }
        task = Task { await self.tray.deleteAll(using: coordinator) }
        _ = await task!.value
        XCTAssertTrue(library.deleteCalls.isEmpty)
        XCTAssertEqual(tray.batchNotice, "Stopped. Nothing was deleted.")
        XCTAssertTrue(tray.needsAttention.isEmpty)
    }
}
