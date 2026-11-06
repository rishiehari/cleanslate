import XCTest
import CleanSlateCore
@testable import CleanSlate

@MainActor
final class InvalidationTests: XCTestCase {
    private var library: FakePhotoLibrary!

    override func setUp() async throws { library = FakePhotoLibrary() }

    private func makeModel(tray: DeletionTray? = nil, policyOpenToNetwork: Bool = false) throws -> CleaningViewModel {
        CleaningViewModel(library: library, tray: tray ?? DeletionTray(fileURL: nil),
                          networkPolicy: NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { policyOpenToNetwork }),
                          store: try LibraryStore(path: nil))
    }

    /// Two exact pairs (A, B) plus unrelated photos, scanned.
    private func scannedModel() async throws -> CleaningViewModel {
        library.add("a1", content: "A", at: 1_000); library.add("a2", content: "A", at: 1_000)
        library.add("b1", content: "B", at: 2_000); library.add("b2", content: "B", at: 2_000)
        library.add("solo1", content: "s1"); library.add("solo2", content: "s2")
        let model = try makeModel()
        await model.runScan()
        XCTAssertEqual(model.groups(in: .exact).count, 2)
        return model
    }

    private func group(_ model: CleaningViewModel, containing id: String) -> PhotoReviewGroup? {
        model.groups.first { $0.all.contains { $0.id == id } }
    }

    // MARK: Groups

    func testUnrelatedChangeLeavesEveryGroupUntouched() async throws {
        let model = try await scannedModel()
        let before = model.groups
        library.update("solo1", revision: "v2")
        let calls = library.digestRequests.count
        await model.processLibraryChange()
        XCTAssertEqual(model.groups.map(\.id), before.map(\.id))
        XCTAssertEqual(library.digestRequests.count, calls, "no group was rehashed")
        XCTAssertTrue(model.recheckingGroupIDs.isEmpty)
    }

    func testChangingAMemberRechecksOnlyThatGroup() async throws {
        let model = try await scannedModel()
        library.update("a2", revision: "v2")                      // same bytes, new revision
        let calls = library.digestRequests.count
        await model.processLibraryChange()
        let rehashed = Set(library.digestRequests.dropFirst(calls).map(\.id))
        XCTAssertEqual(rehashed, ["a1", "a2"], "only group A was rechecked")
        XCTAssertEqual(model.groups(in: .exact).count, 2, "A is still identical, so it stays")
        XCTAssertEqual(group(model, containing: "a2")?.candidates.first { $0.id == "a2" }?.record.revision
                       ?? group(model, containing: "a2")?.keeper.record.revision, "v2", "the group holds the fresh revision")
    }

    func testDeletingTheKeeperDissolvesTheGroup() async throws {
        let model = try await scannedModel()
        let keeperID = group(model, containing: "a1")!.keeper.id
        library.assets[keeperID] = nil; library.recordChange(deleted: [keeperID])
        await model.processLibraryChange()
        XCTAssertNil(group(model, containing: "a1"))
        XCTAssertNotNil(group(model, containing: "b1"), "the other group is untouched")
    }

    func testDeletingOneOfThreeCopiesShrinksTheGroup() async throws {
        library.add("c1", content: "C", at: 3_000); library.add("c2", content: "C", at: 3_000); library.add("c3", content: "C", at: 3_000)
        let model = try makeModel(); await model.runScan()
        let original = group(model, containing: "c1")!
        let victim = original.candidates[0].id
        library.assets[victim] = nil; library.recordChange(deleted: [victim])
        await model.processLibraryChange()
        let updated = try XCTUnwrap(group(model, containing: original.keeper.id))
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.all.count, 2)
        XCTAssertFalse(updated.all.contains { $0.id == victim })
    }

    func testFavoritingACopyMakesItTheKeeperAndNeverDeletable() async throws {
        let model = try await scannedModel()
        let original = group(model, containing: "a1")!
        let other = original.candidates[0].id
        library.update(other, revision: "fav", flags: [.favorite])
        await model.processLibraryChange()
        let updated = try XCTUnwrap(group(model, containing: other))
        XCTAssertEqual(updated.keeper.id, other, "the favorite is kept")
        XCTAssertEqual(SafetyPolicy.evaluate(updated.coreCluster).preselected, [original.keeper.id])
    }

    func testContentChangeDissolvesAnExactGroup() async throws {
        let model = try await scannedModel()
        library.assets["a2"]?.digests = [FakePhotoLibrary.digest("edited")]
        library.update("a2", revision: "v2")
        await model.processLibraryChange()
        XCTAssertNil(group(model, containing: "a1"), "no longer byte-identical")
        XCTAssertNotNil(group(model, containing: "b1"))
    }

    func testUnavailableOriginalDissolvesTheGroupInsteadOfTrustingIt() async throws {
        let model = try await scannedModel()
        library.assets["a2"]?.digests = nil
        library.update("a2", revision: "v2")
        await model.processLibraryChange()
        XCTAssertNil(group(model, containing: "a1"))
    }

    func testExpiredHistoryClearsResultsWithAMessage() async throws {
        let model = try await scannedModel()
        library.changeTokensExpired = true
        library.update("a2", revision: "v2")
        await model.processLibraryChange()
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertTrue(model.statusMessage?.contains("Scan again") == true)
    }

    func testChangesAreAppliedToTheIndexToo() async throws {
        let model = try await scannedModel()
        library.add("fresh", content: "F")
        await model.processLibraryChange()
        let stored = await model.store.snapshots(ids: ["fresh"])
        XCTAssertNotNil(stored["fresh"])
    }

    /// Property: after ANY sequence of library changes, no group on screen contains a photo whose current
    /// revision differs from the revision the group holds.
    func testNoGroupIsEverFreshWhileHoldingAStaleMember() async throws {
        var rng = SystemRandomNumberGenerator()
        for round in 0..<12 {
            library = FakePhotoLibrary()
            for n in 0..<40 {
                library.add("r\(round)p\(n)a", content: "c\(n)", at: Int64(10_000 + n * 100))
                library.add("r\(round)p\(n)b", content: "c\(n)", at: Int64(10_000 + n * 100))
            }
            for n in 0..<40 { library.add("r\(round)s\(n)", content: "solo\(n)") }
            let model = try makeModel(); await model.runScan()
            XCTAssertEqual(model.groups(in: .exact).count, 40)
            let ids = Array(library.assets.keys)
            for step in 0..<10 {
                for _ in 0..<Int.random(in: 1...6, using: &rng) {
                    let id = ids.randomElement(using: &rng)!
                    guard library.assets[id] != nil else { continue }
                    switch Int.random(in: 0..<5, using: &rng) {
                    case 0: library.assets[id] = nil; library.recordChange(deleted: [id])
                    case 1: library.update(id, revision: "rev\(round)-\(step)-\(Int.random(in: 0..<999, using: &rng))")
                    case 2: library.update(id, revision: "fav\(step)\(Int.random(in: 0..<999, using: &rng))", flags: [.favorite])
                    case 3: library.assets[id]?.digests = [FakePhotoLibrary.digest("x\(Int.random(in: 0..<9999, using: &rng))")]
                            library.update(id, revision: "edit\(step)\(Int.random(in: 0..<999, using: &rng))")
                    default: library.update(id, revision: "touch\(step)\(Int.random(in: 0..<999, using: &rng))")
                    }
                }
                await model.processLibraryChange()
                for group in model.groups {
                    for member in group.all {
                        guard let current = library.assets[member.id]?.snapshot else { return XCTFail("group holds a deleted photo \(member.id)") }
                        XCTAssertEqual(current.record.revision, member.record.revision, "stale member \(member.id) in a fresh group")
                    }
                }
            }
        }
    }

    // MARK: Tray

    private func approvedTray(_ model: CleaningViewModel, keeper: String = "a1") -> TrayEntry {
        let group = self.group(model, containing: keeper)!
        let selected = SafetyPolicy.evaluate(group.coreCluster).preselected
        model.tray.approve(group: group, selected: selected, manuallyReviewed: [])
        return model.tray.entries[0]
    }

    func testFavoritingAnApprovedPhotoMovesItToNeedsAnotherLook() async throws {
        let model = try await scannedModel()
        let entry = approvedTray(model)
        XCTAssertEqual(model.tray.photoCount, 1)
        library.update(entry.selectedIDs.first!, revision: "fav", flags: [.favorite])
        await model.processLibraryChange()
        XCTAssertEqual(model.tray.needsAttention[entry.id], "You favorited one of these photos")
        XCTAssertEqual(model.tray.photoCount, 0, "it no longer counts toward what will be deleted")
        XCTAssertFalse(model.tray.hasReadyItems)
        await model.deleteTray()
        XCTAssertTrue(library.deleteCalls.isEmpty, "a flagged entry is never deleted")
    }

    func testAnApprovedPhotoDeletedElsewhereIsFlagged() async throws {
        let model = try await scannedModel()
        let entry = approvedTray(model)
        let victim = entry.selectedIDs.first!
        library.assets[victim] = nil; library.recordChange(deleted: [victim])
        await model.processLibraryChange()
        XCTAssertEqual(model.tray.needsAttention[entry.id], "A photo was already deleted")
    }

    func testUnrelatedChangesDoNotFlagTheTray() async throws {
        let model = try await scannedModel()
        let entry = approvedTray(model)
        library.update("solo1", revision: "v2")
        await model.processLibraryChange()
        XCTAssertNil(model.tray.needsAttention[entry.id])
        XCTAssertEqual(model.tray.photoCount, 1)
    }

    func testPuttingAnEntryBackReturnsItToTheInbox() async throws {
        let model = try await scannedModel()
        let entry = approvedTray(model)
        XCTAssertTrue(model.tray.reviewedGroupIDs.contains(entry.id))
        model.tray.sendBackToReview(entry.id)
        XCTAssertFalse(model.tray.reviewedGroupIDs.contains(entry.id))
        XCTAssertTrue(model.tray.entries.isEmpty)
    }

    func testTrayIsRevalidatedWhenTheAppStartsAgain() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tray-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = try makeModel(tray: DeletionTray(fileURL: url))
        library.add("a1", content: "A", at: 1_000); library.add("a2", content: "A", at: 1_000)
        await first.runScan()
        let entry = approvedTray(first)
        library.update(entry.selectedIDs.first!, revision: "fav", flags: [.favorite])      // changed while the app was closed
        let relaunched = try makeModel(tray: DeletionTray(fileURL: url))
        XCTAssertEqual(relaunched.tray.needsAttention[entry.id], "You favorited one of these photos")
    }

    func testStandaloneEntryThatBecameAFavoriteIsFlagged() async throws {
        library.add("s1", subtypes: 1 << 2, size: 100); library.add("s2", subtypes: 1 << 2, size: 100)
        let model = try makeModel(); await model.runScan()
        model.tray.approveStandalone(items: model.standalone(in: .screenshots))
        library.update("s1", revision: "fav", flags: [.favorite])
        await model.processLibraryChange()
        XCTAssertEqual(model.tray.needsAttention.values.first, "You favorited one of these photos")
        XCTAssertEqual(model.tray.photoCount, 0)
    }

    func testStandaloneListsDropDeletedItemsAndRefreshChangedOnes() async throws {
        library.add("s1", subtypes: 1 << 2, size: 100); library.add("s2", subtypes: 1 << 2, size: 100)
        let model = try makeModel(); await model.runScan()
        XCTAssertEqual(model.standalone(in: .screenshots).count, 2)
        library.assets["s1"] = nil; library.recordChange(deleted: ["s1"])
        await model.processLibraryChange()
        XCTAssertEqual(model.standalone(in: .screenshots).map(\.id), ["s2"])
        library.update("s2", revision: "fav", flags: [.favorite])
        await model.processLibraryChange()
        XCTAssertTrue(model.standalone(in: .screenshots).isEmpty, "a favorite leaves the keeper-less list")
    }
}
