import XCTest
import CleanSlateCore
@testable import CleanSlate

/// N05 C5: approved tray entries are invalidated when a rule covers them, and stay invalidated.
@MainActor
final class ProtectionTrayTests: XCTestCase {
    private var library: FakePhotoLibrary!
    private var tray: DeletionTray!
    private var service: ProtectionRuleService!
    private var model: CleaningViewModel!
    private var suites: [String] = []
    private var paths: [String] = []

    override func setUp() async throws {
        library = FakePhotoLibrary()
        tray = DeletionTray(fileURL: nil)
        service = try makeService()
        await service.load()
        model = makeModel(tray: tray, service: service)
    }

    override func tearDown() async throws {
        for suite in suites { UserDefaults().removePersistentDomain(forName: suite) }
        for path in paths { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
    }

    private func makeService(defaults: UserDefaults? = nil, path: String? = nil) throws -> ProtectionRuleService {
        let name = "org.cleanslate.test.tray.\(UUID().uuidString)"
        suites.append(name)
        let file = path ?? FileManager.default.temporaryDirectory.appendingPathComponent("tray-\(UUID().uuidString).sqlite").path
        paths.append(file)
        return ProtectionRuleService(store: try LibraryStore(path: file), defaults: defaults ?? UserDefaults(suiteName: name)!)
    }
    private func makeModel(tray: DeletionTray, service: ProtectionRuleService) -> CleaningViewModel {
        CleaningViewModel(library: library, tray: tray,
                          networkPolicy: NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { false }),
                          store: try! LibraryStore(path: nil), protection: service)
    }
    private func approve(_ i: Int, into tray: DeletionTray? = nil) {
        library.add("k\(i)", content: "c\(i)", at: Int64(1_000 + i)); library.add("c\(i)", content: "c\(i)", at: Int64(1_000 + i))
        (tray ?? self.tray).approve(group: library.exactGroup(keeper: "k\(i)", copies: ["c\(i)"], bytes: 100), selected: ["c\(i)"], manuallyReviewed: [])
    }
    private func tempTrayURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tray-\(UUID().uuidString).json")
        paths.append(url.path)
        return url
    }

    // MARK: G1 - protecting an approved target

    func testProtectingTargetMarksNeedsAttentionBeforeAnyDelete() async {
        approve(0); approve(1)
        let ok = await service.protect(assetIDs: ["c0"])
        XCTAssertTrue(ok)
        XCTAssertEqual(tray.needsAttention["test-k0"], TrayChecker.protectedByRuleReason)
        XCTAssertNil(tray.needsAttention["test-k1"])
        XCTAssertEqual(tray.readyEntries.map(\.id), ["test-k1"])
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testProtectedKeeperDoesNotInvalidateTheEntry() async {
        approve(0)
        _ = await service.protect(assetIDs: ["k0"])
        XCTAssertTrue(tray.needsAttention.isEmpty)
        XCTAssertEqual(tray.readyEntries.count, 1)
    }

    func testProtectingStandaloneItemInvalidatesItsEntry() async {
        library.add("s1", subtypes: 1 << 2, size: 10); library.add("s2", subtypes: 1 << 2, size: 10)
        tray.approveStandalone(items: ["s1", "s2"].map { StandaloneItem(snapshot: library.assets[$0]!.snapshot, verifiedBytes: 10) })
        _ = await service.protect(assetIDs: ["s2"])
        let id = tray.standaloneEntries[0].id
        XCTAssertEqual(tray.needsAttention[id], TrayChecker.protectedByRuleReason)
        XCTAssertTrue(tray.readyStandaloneEntries.isEmpty)
    }

    func testDateRuleInvalidatesMatchingEntries() async throws {
        approve(0)
        let day = try XCTUnwrap(LocalDay("2026-06-10"))
        // Captured 1970 in the fake, so a 2026 range must not match; a 1970 range must.
        _ = await service.protect(range: day...day, timeZoneID: "UTC")
        XCTAssertTrue(tray.needsAttention.isEmpty)
        let epoch = try XCTUnwrap(LocalDay("1970-01-01"))
        _ = await service.protect(range: epoch...epoch, timeZoneID: "UTC")
        XCTAssertEqual(tray.needsAttention["test-k0"], TrayChecker.protectedByRuleReason)
    }

    func testProductionDeletePathDeletesNothingForAProtectedEntry() async {
        approve(0); approve(1)
        _ = await service.protect(assetIDs: ["c1"])
        let removed = await model.deleteTray()
        XCTAssertEqual(library.deleteCalls, [["c0"]], "only the unprotected entry went to Apple")
        XCTAssertTrue(removed)
        XCTAssertFalse(library.deleteCalls.joined().contains("c1"))
        XCTAssertNotNil(library.assets["c1"])
    }

    func testReloadRevalidatesEverythingAlreadyInTheTray() async throws {
        // Rules exist on disk; the app relaunches with an approved tray and the rules finish loading afterwards.
        let defaults = UserDefaults(suiteName: "org.cleanslate.test.reload.\(UUID().uuidString)")!
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("reload-\(UUID().uuidString).sqlite").path
        paths.append(path)
        let first = try makeService(defaults: defaults, path: path)
        await first.load()
        _ = await first.protect(assetIDs: ["c0"])
        approve(0)
        let relaunched = try makeService(defaults: defaults, path: path)
        let relaunchedModel = makeModel(tray: tray, service: relaunched)
        XCTAssertTrue(tray.needsAttention.isEmpty, "not loaded yet: the check is skipped, and not sticky")
        await relaunched.load()
        XCTAssertEqual(tray.needsAttention["test-k0"], TrayChecker.protectedByRuleReason)
        XCTAssertNotNil(relaunchedModel)
    }

    func testLoadingStateIsNotSticky() async throws {
        approve(0)
        let slow = try makeService()
        let other = makeModel(tray: tray, service: slow)           // never loaded
        other.revalidateTray(touched: nil)
        XCTAssertTrue(tray.needsAttention.isEmpty)
        XCTAssertEqual(tray.readyEntries.count, 1, "the commit gate, not the tray, blocks while loading")
    }

    // MARK: G4 - removing a rule does not resurrect

    func testRemovingRuleKeepsEntryNeedingReview() async throws {
        approve(0)
        _ = await service.protect(assetIDs: ["c0"])
        let rule = try XCTUnwrap(service.rules.first)
        _ = await service.remove(ruleID: rule.id)
        XCTAssertEqual(tray.needsAttention["test-k0"], TrayChecker.protectedByRuleReason)
        XCTAssertTrue(tray.readyEntries.isEmpty)
        model.revalidateTray(touched: nil)
        XCTAssertTrue(tray.readyEntries.isEmpty, "a recompute must not bring it back")
        let receipt = await tray.deleteAll(using: coordinatorForTray())
        XCTAssertNil(receipt)
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testRemoveAllRulesAlsoKeepsEntryOut() async {
        approve(0)
        _ = await service.protect(assetIDs: ["c0"])
        _ = await service.removeAll()
        XCTAssertTrue(tray.readyEntries.isEmpty)
    }

    func testStickyInvalidationSurvivesTrayReload() async {
        let url = tempTrayURL()
        let persisted = DeletionTray(fileURL: url)
        let persistedModel = makeModel(tray: persisted, service: service)
        approve(0, into: persisted)
        _ = await service.protect(assetIDs: ["c0"])
        XCTAssertTrue(persisted.readyEntries.isEmpty)
        _ = await service.removeAll()
        let reloaded = DeletionTray(fileURL: url)
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertTrue(reloaded.readyEntries.isEmpty, "still needs a fresh look after relaunch, with the rule gone")
        XCTAssertEqual(reloaded.needsAttention["test-k0"], TrayChecker.protectedByRuleReason)
        XCTAssertNotNil(persistedModel)
    }

    func testOldTrayJSONWithoutTheNewFieldStillDecodes() throws {
        let url = tempTrayURL()
        let writer = DeletionTray(fileURL: url)
        approve(0, into: writer)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json.removeValue(forKey: "protectionInvalidated")
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let reader = DeletionTray(fileURL: url)
        XCTAssertEqual(reader.entries.count, 1)
        XCTAssertEqual(reader.readyEntries.count, 1)
    }

    func testStickyIsClearedBySendBackToReviewRemoveClearAndReapprove() async {
        for action in 0..<4 {
            let t = DeletionTray(fileURL: nil)
            let m = makeModel(tray: t, service: service)
            let id = "test-k\(action)"
            approve(action, into: t)
            t.markProtectionInvalidated([id])
            XCTAssertTrue(t.readyEntries.isEmpty)
            switch action {
            case 0: t.sendBackToReview(id)
            case 1: t.remove(groupID: id)
            case 2: t.clear()
            default: t.approve(group: library.exactGroup(keeper: "k3", copies: ["c3"], bytes: 100), selected: ["c3"], manuallyReviewed: [])
            }
            XCTAssertNil(t.needsAttention[id], "action \(action)")
            XCTAssertTrue(t.protectionInvalidatedIDs.isEmpty, "action \(action)")
            if action == 0 || action == 1 || action == 2 { XCTAssertTrue(t.entries.isEmpty) } else { XCTAssertEqual(t.readyEntries.count, 1) }
            XCTAssertNotNil(m)
        }
    }

    func testUndoingAReapprovalRestoresTheStickyState() {
        approve(0)
        tray.markProtectionInvalidated(["test-k0"])
        tray.approve(group: library.exactGroup(keeper: "k0", copies: ["c0"], bytes: 100), selected: ["c0"], manuallyReviewed: [])
        XCTAssertEqual(tray.readyEntries.count, 1, "re-approved by the user")
        tray.undo()
        XCTAssertTrue(tray.readyEntries.isEmpty, "undo must not resurrect an invalidated entry")
    }

    func testDeletedEntriesLeaveNoStickyResidue() async {
        approve(0); approve(1)
        tray.markProtectionInvalidated(["test-k0"])
        _ = await model.deleteTray()
        tray.remove(groupID: "test-k0")
        XCTAssertTrue(tray.protectionInvalidatedIDs.isEmpty)
    }

    // MARK: deleteAll gate reasons become sticky

    func testBlockedByRuleDuringDeleteBecomesSticky() async {
        approve(0); approve(1)
        let gate = StaticProtectionGate(protected: ["c1"])
        let coordinator = PhotoDeletionCoordinator(library: library,
            networkPolicy: NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { false }), protection: gate)
        let receipt = await tray.deleteAll(using: coordinator)
        XCTAssertNil(receipt)
        XCTAssertEqual(tray.needsAttention["test-k1"], TrayChecker.protectedByRuleReason)
        gate.protectedIDs = []                                     // the rule goes away
        XCTAssertFalse(tray.readyEntries.contains { $0.id == "test-k1" })
        XCTAssertTrue(tray.protectionInvalidatedIDs.contains("test-k1"))
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testOtherBlockReasonsAreNotSticky() async {
        approve(0)
        library.update("c0", flags: [.favorite])
        let gate = StaticProtectionGate()
        let coordinator = PhotoDeletionCoordinator(library: library,
            networkPolicy: NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { false }), protection: gate)
        _ = await tray.deleteAll(using: coordinator)
        XCTAssertNotNil(tray.needsAttention["test-k0"])
        XCTAssertTrue(tray.protectionInvalidatedIDs.isEmpty)
    }

    private func coordinatorForTray() -> PhotoDeletionCoordinator {
        PhotoDeletionCoordinator(library: library,
            networkPolicy: NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { false }), protection: service)
    }
}
