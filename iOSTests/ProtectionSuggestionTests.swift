import XCTest
import CleanSlateCore
@testable import CleanSlate

/// N05 C6: protected photos are never suggested, never pre-marked, and stay out within a session.
@MainActor
final class ProtectionSuggestionTests: XCTestCase {
    private var library: FakePhotoLibrary!
    private var gate: StaticProtectionGate!
    private var tray: DeletionTray!
    private var model: CleaningViewModel!
    private let screenshot: UInt = 1 << 2

    override func setUp() async throws {
        library = FakePhotoLibrary()
        gate = StaticProtectionGate()
        tray = DeletionTray(fileURL: nil)
        model = CleaningViewModel(library: library, tray: tray,
                                  networkPolicy: NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { false }),
                                  store: try LibraryStore(path: nil), protection: gate)
    }

    private func exact(_ keeper: String, _ copies: [String]) -> PhotoReviewGroup {
        for id in [keeper] + copies { library.add(id, content: keeper, at: 1_000) }
        return library.exactGroup(keeper: keeper, copies: copies, bytes: 10)
    }
    private func shots(_ ids: [String]) -> [StandaloneItem] {
        ids.map { id in
            library.add(id, subtypes: screenshot, size: 100)
            return StandaloneItem(snapshot: library.assets[id]!.snapshot, verifiedBytes: 100)
        }
    }
    private func review(_ group: PhotoReviewGroup) -> GroupReviewModel {
        GroupReviewModel(group: group, tray: tray, haptics: HapticsService(), protection: model.protection)
    }

    // MARK: Groups

    func testProtectedCopyIsNeverPreselectedInAGroupThatStillHasAnotherCopy() {
        let group = exact("k", ["c1", "c2"])
        gate.protectedIDs = ["c1"]
        model.seedGroupsForUITesting([group])
        XCTAssertEqual(model.groups.map(\.id), [group.id], "another copy is still actionable, so the group stays")
        let r = review(model.groups[0])
        XCTAssertEqual(r.draft.deleteIDs, ["c2"])
        XCTAssertEqual(r.decision(for: "c1"), .protected(reason: "Protected by your rule — always kept"))
        r.set("c1", to: .delete)
        XCTAssertFalse(r.draft.deleteIDs.contains("c1"), "tapping a protected copy cannot mark it")
        XCTAssertTrue(r.group.candidates.first { $0.id == "c1" }!.record.flags.contains(.userProtected), "shows the lock")
    }

    func testGroupWhoseOnlyCopyIsProtectedIsWithheld() {
        let group = exact("k", ["c"])
        gate.protectedIDs = ["c"]
        model.seedGroupsForUITesting([group])
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertEqual(model.hiddenByRulesGroupIDs, [group.id])
        XCTAssertTrue(model.groups(in: .exact).isEmpty)
    }

    func testProtectedKeeperGroupIsStillOfferedAndDeletesTheOtherCopy() {
        let group = exact("k", ["c"])
        gate.protectedIDs = ["k"]
        model.seedGroupsForUITesting([group])
        XCTAssertEqual(model.groups.count, 1)
        XCTAssertEqual(review(model.groups[0]).draft.deleteIDs, ["c"])
        XCTAssertTrue(model.hiddenByRulesGroupIDs.isEmpty)
    }

    func testSimilarGroupWithOnlyProtectedCandidatesIsWithheld() {
        for id in ["a", "b"] { library.add(id) }
        let set = library.reviewSet(["a", "b"])
        gate.protectedIDs = ["a", "b"]
        model.seedGroupsForUITesting([set])
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertEqual(model.hiddenByRulesGroupIDs, [set.id])
    }

    func testNewRuleWithdrawsAGroupThatIsAlreadyListed() {
        let group = exact("k", ["c"])
        model.seedGroupsForUITesting([group])
        XCTAssertEqual(model.groups.count, 1)
        gate.protectedIDs = ["c"]
        model.protectionDidChange(.added)
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertEqual(model.hiddenByRulesGroupIDs, [group.id])
    }

    // MARK: Approve all (E11)

    func testApproveAllSkipsUserProtectedCopies() {
        let group = exact("k", ["c1", "c2"])
        gate.protectedIDs = ["c1"]
        model.seedGroupsForUITesting([group])
        XCTAssertEqual(model.approvableCopies(in: model.groups[0]), ["c2"])
        tray.approveAll([(group: model.groups[0], selected: model.approvableCopies(in: model.groups[0]))])
        XCTAssertEqual(tray.entries.first?.selectedIDs, ["c2"])
        XCTAssertFalse(tray.entries.flatMap(\.selectedIDs).contains("c1"))
    }

    func testApproveAllIsHiddenAndEmptyWhenRulesAreNotReady() {
        let group = exact("k", ["c"])
        model.seedGroupsForUITesting([group])
        XCTAssertTrue(model.protectionIsReady)
        XCTAssertEqual(model.approvableCopies(in: group), ["c"])
        for state: ProtectionAvailability in [.loading, .unavailable("x"), .lost] {
            gate.availability = state
            XCTAssertFalse(model.protectionIsReady)
            XCTAssertTrue(model.approvableCopies(in: group).isEmpty, "\(state)")
        }
        gate.availability = .ready
        gate.pendingWrites = 1
        XCTAssertTrue(model.approvableCopies(in: group).isEmpty, "a pending write also hides it")
    }

    // MARK: Standalone (E12)

    func testProtectedScreenshotHiddenAndNotCommittable() async {
        let items = shots(["s1", "s2"])
        gate.protectedIDs = ["s1"]
        model.seedGroupsForUITesting([], standalone: items)
        XCTAssertEqual(model.standalone(in: .screenshots).map(\.id), ["s2"])
        let coordinator = PhotoDeletionCoordinator(library: library,
            networkPolicy: NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { false }), protection: gate)
        do { _ = try await coordinator.commitStandalone(items: [items[0]]); XCTFail("must throw") }
        catch { XCTAssertEqual(error as? PhotoDeletionCoordinator.DeletionError, .unsafe("protected")) }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testStandaloneListIsEmptyWhileRulesAreUnavailable() {
        gate.availability = .unavailable("x")
        model.seedGroupsForUITesting([], standalone: shots(["s1", "s2"]))
        XCTAssertTrue(model.standalone(in: .screenshots).isEmpty, "fail closed")
        gate.availability = .ready
        model.protectionDidChange(.reloaded)
        XCTAssertEqual(Set(model.standalone(in: .screenshots).map(\.id)), ["s1", "s2"])
    }

    func testApproveStandaloneGuardRefusesProtectedItems() {
        let items = shots(["s1", "s2"])
        model.seedGroupsForUITesting([], standalone: items)
        gate.protectedIDs = ["s1"]                                   // protected after it was listed
        XCTAssertFalse(model.approveStandalone(items))
        XCTAssertEqual(tray.standaloneEntries.flatMap { $0.items.map(\.id) }, ["s2"])
        let clean = shots(["s3"])
        XCTAssertTrue(model.approveStandalone(clean))
    }

    func testSelectionBlockReasonNamesTheRule() {
        let items = shots(["s1"])
        model.seedGroupsForUITesting([], standalone: items)
        XCTAssertNil(model.selectionBlockReason(for: items[0]))
        gate.protectedIDs = ["s1"]
        XCTAssertEqual(model.selectionBlockReason(for: items[0]), "Protected by your rule — always kept")
    }

    // MARK: Session shield (E13)

    func testRemovingRuleDoesNotRemarkExactCopyInSession() {
        let group = exact("k", ["c"])
        gate.protectedIDs = ["c"]
        model.seedGroupsForUITesting([group])
        XCTAssertTrue(model.groups.isEmpty)
        gate.protectedIDs = []                                       // the rule is removed mid-session
        model.protectionDidChange(.removed)
        XCTAssertTrue(model.groups.isEmpty, "no new suggestions until the next scan")
        XCTAssertEqual(model.hiddenByRulesGroupIDs, [group.id])
        model.protectionDidChange(.reloaded)
        XCTAssertTrue(model.groups.isEmpty, "even a reload keeps what the session already shielded")
        // A new scan (results reset) starts clean.
        model.seedGroupsForUITesting([group])
        XCTAssertEqual(model.groups.map(\.id), [group.id])
        XCTAssertTrue(model.hiddenByRulesGroupIDs.isEmpty)
    }

    func testShieldOnlyGrowsWithinASession() {
        let items = shots(["s1"])
        gate.protectedIDs = ["s1"]
        model.seedGroupsForUITesting([], standalone: items)
        XCTAssertTrue(model.standalone(in: .screenshots).isEmpty)
        gate.protectedIDs = []
        XCTAssertFalse(model.protection.verdict(for: items[0].snapshot).allowsRemoval, "still shielded this session")
        XCTAssertFalse(model.approveStandalone(items))
        model.resetResults()
        XCTAssertTrue(model.protection.verdict(for: items[0].snapshot).allowsRemoval, "cleared by the next scan")
    }

    // MARK: Rules not ready at scan time

    func testGroupsFoundWhileRulesLoadAreWithheldThenRestoredOnReload() {
        gate.availability = .loading
        let group = exact("k", ["c"])
        model.seedGroupsForUITesting([group])
        XCTAssertTrue(model.groups.isEmpty, "fail closed while rules are not ready")
        XCTAssertTrue(model.hiddenByRulesGroupIDs.isEmpty, "not claimed to be protected by a rule")
        gate.availability = .ready
        model.protectionDidChange(.reloaded)
        XCTAssertEqual(model.groups.map(\.id), [group.id])
    }

    func testGroupsFoundWhileRulesLoadStayWithheldIfTheyTurnOutProtected() {
        gate.availability = .loading
        let group = exact("k", ["c"])
        model.seedGroupsForUITesting([group])
        gate.availability = .ready
        gate.protectedIDs = ["c"]
        model.protectionDidChange(.reloaded)
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertEqual(model.hiddenByRulesGroupIDs, [group.id])
    }

    // MARK: GroupReviewModel without a gate fails closed

    func testReviewWithoutAnyGateCannotApprove() {
        let group = exact("k", ["c"])
        let bare = GroupReviewModel(group: group, tray: DeletionTray(fileURL: nil), haptics: HapticsService())
        XCTAssertFalse(bare.approve())
        XCTAssertEqual(bare.notice, GroupReviewModel.rulesNotReadyNotice)
    }

    func testReviewFindsTheTrayGateWhenNoneIsPassed() {
        let group = exact("k", ["c"])
        let viaTray = GroupReviewModel(group: group, tray: tray, haptics: HapticsService())     // CleaningViewModel set tray.protectionGate
        XCTAssertTrue(viaTray.approve())
    }

    // MARK: Cost (10k assets)

    func testRedecorationCostWithTenThousandAssets() {
        let pairs = 5_000
        var groups: [PhotoReviewGroup] = []
        groups.reserveCapacity(pairs)
        func snap(_ id: String, _ t: Int) -> PhotoSnapshot {
            PhotoSnapshot(id: id, record: AssetRecord(id: id, revision: "v1"), capturedAt: Date(timeIntervalSince1970: TimeInterval(t)),
                          burstID: nil, width: 10, height: 10)
        }
        for i in 0..<pairs {
            let keeper = snap("k\(i)", i), copy = snap("c\(i)", i)
            groups.append(PhotoReviewGroup(id: "g\(i)", kind: .exact, keeper: keeper, candidates: [copy],
                                           evidence: [PairEvidence(first: keeper.id, second: copy.id, relation: .exactResources, completeResourceEquality: true)],
                                           verifiedCandidateBytes: [copy.id: 10]))
        }
        model.seedGroupsForUITesting(groups)
        XCTAssertEqual(model.groups.count, pairs)
        // 500 rules arrive at once (a static gate stands in for the rule set).
        gate.protectedIDs = Set((0..<500).map { "c\($0 * 10)" })
        let clock = ContinuousClock()
        let elapsed = clock.measure { model.protectionDidChange(.added) }
        let ms = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
        print("N05 C6 redecoration of \(pairs * 2) assets / \(pairs) groups, 500 rules: \(ms) ms on the main actor")
        XCTAssertEqual(model.groups.count, pairs - 500)
        XCTAssertEqual(model.hiddenByRulesGroupIDs.count, 500)
        XCTAssertLessThan(ms, 250)
    }
}
