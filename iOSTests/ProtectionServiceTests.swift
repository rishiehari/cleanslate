import XCTest
import CleanSlateCore
@testable import CleanSlate

/// N05 C3: the rule service state machine, sentinel and pending-write semantics.
@MainActor
final class ProtectionServiceTests: XCTestCase {
    private var suites: [String] = []
    private var paths: [String] = []

    override func tearDown() async throws {
        for suite in suites { UserDefaults().removePersistentDomain(forName: suite) }
        for path in paths { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        suites = []; paths = []
    }

    private func defaults() -> UserDefaults {
        let name = "org.cleanslate.test.protection.\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }
    private func tempPath() -> String {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("svc-\(UUID().uuidString).sqlite").path
        paths.append(path)
        return path
    }
    private func photo(_ id: String, at: TimeInterval? = 1_000, flags: Set<PreservationFlag> = []) -> PhotoSnapshot {
        PhotoSnapshot(id: id, record: AssetRecord(id: id, revision: "r1", flags: flags),
                      capturedAt: at.map { Date(timeIntervalSince1970: $0) }, burstID: nil, width: 10, height: 10)
    }
    private func durableService(_ defaults: UserDefaults, path: String? = nil) throws -> (ProtectionRuleService, LibraryStore) {
        let store = try LibraryStore(path: path ?? tempPath())
        return (ProtectionRuleService(store: store, defaults: defaults), store)
    }

    func testNewServiceIsLoadingAndBlocksEverythingUntilLoaded() throws {
        let (service, _) = try durableService(defaults())
        XCTAssertEqual(service.availability, .loading)
        XCTAssertEqual(service.verdict(for: photo("a")), .indeterminate(.rulesLoading))
        XCTAssertNotNil(service.commitBlock(since: service.revision))
    }

    func testLoadEmptyStoreIsReadyAndUnprotected() async throws {
        let (service, _) = try durableService(defaults())
        await service.load()
        XCTAssertEqual(service.availability, .ready)
        XCTAssertEqual(service.verdict(for: photo("a")), .unprotected)
        XCTAssertNil(service.commitBlock(since: service.revision))
    }

    func testFallbackStoreWithoutPriorRulesDoesNotRegressDeletion() async throws {
        let service = ProtectionRuleService(store: try LibraryStore(path: nil), defaults: defaults())
        await service.load()
        XCTAssertEqual(service.availability, .ready)
        XCTAssertNil(service.commitBlock(since: service.revision))
        XCTAssertEqual(service.verdict(for: photo("a")), .unprotected)
        // ...but a non-durable store refuses to create rules it could not keep.
        let ok = await service.protect(assetIDs: ["a"])
        XCTAssertFalse(ok)
        XCTAssertNotNil(service.lastError)
        XCTAssertEqual(service.verdict(for: photo("a")), .unprotected)
    }

    func testFallbackStoreAfterRulesWereCreatedIsUnavailable() async throws {
        let d = defaults()
        let (first, _) = try durableService(d)
        await first.load()
        let created = await first.protect(assetIDs: ["a"])
        XCTAssertTrue(created)
        let fallback = ProtectionRuleService(store: try LibraryStore(path: nil), defaults: d)
        await fallback.load()
        guard case .unavailable = fallback.availability else { return XCTFail("expected unavailable, got \(fallback.availability)") }
        XCTAssertEqual(fallback.verdict(for: photo("zzz")), .indeterminate(.rulesUnavailable))
        XCTAssertNotNil(fallback.commitBlock(since: fallback.revision))
    }

    func testReadFailureWithPriorRulesIsUnavailable() async throws {
        let d = defaults()
        let (service, store) = try durableService(d)
        await service.load()
        let created = await service.protect(assetIDs: ["a"])
        XCTAssertTrue(created)
        try await store.debugExecute("DROP TABLE protection_rules")
        await service.load()
        guard case .unavailable = service.availability else { return XCTFail("expected unavailable, got \(service.availability)") }
        XCTAssertFalse(service.verdict(for: photo("a")).allowsRemoval)
        XCTAssertFalse(service.verdict(for: photo("b")).allowsRemoval)
    }

    func testMalformedRowIsUnavailableEvenWhenDefaultsSayNeverCreated() async throws {
        // Rows exist, so rules were created, whatever UserDefaults says: never read this as "no rules".
        let (service, store) = try durableService(defaults())
        try await store.debugExecute("INSERT INTO protection_rules(rule_id,kind,target_id,created_at,updated_at) VALUES('not-a-uuid','asset','A',1,1)")
        await service.load()
        guard case .unavailable = service.availability else { return XCTFail("expected unavailable, got \(service.availability)") }
        XCTAssertFalse(service.verdict(for: photo("other")).allowsRemoval)
    }

    func testReadFailureWithoutPriorRulesIsReady() async throws {
        let (service, store) = try durableService(defaults())
        try await store.debugExecute("DROP TABLE protection_rules")
        await service.load()
        XCTAssertEqual(service.availability, .ready)
    }

    func testRevisionBelowMirrorIsLostUntilAcknowledged() async throws {
        let d = defaults()
        let (first, _) = try durableService(d)
        await first.load()
        let created = await first.protect(assetIDs: ["a"])
        XCTAssertTrue(created)
        XCTAssertEqual(first.revision, 2)
        // A restored backup or replaced database: a brand-new store, same UserDefaults.
        let (second, _) = try durableService(d)
        await second.load()
        XCTAssertEqual(second.availability, .lost)
        XCTAssertEqual(second.verdict(for: photo("a")), .indeterminate(.rulesUnavailable))
        XCTAssertNotNil(second.commitBlock(since: second.revision))
        let refused = await second.protect(assetIDs: ["b"])
        XCTAssertFalse(refused, "no writes while the state is lost")
        second.acknowledgeLost()
        XCTAssertEqual(second.availability, .ready)
        XCTAssertNil(second.commitBlock(since: second.revision))
        // The acknowledgement is remembered: a later load does not re-lose.
        await second.load()
        XCTAssertEqual(second.availability, .ready)
    }

    func testFailedWriteLeavesUnprotectedWithError() async throws {
        let (service, store) = try durableService(defaults())
        await service.load()
        await store.debugFailNextProtectionWrite()
        let ok = await service.protect(assetIDs: ["a"])
        XCTAssertFalse(ok)
        XCTAssertNotNil(service.lastError)
        XCTAssertEqual(service.pendingWrites, 0)
        XCTAssertEqual(service.verdict(for: photo("a")), .unprotected, "no shield before the write is durable")
        XCTAssertTrue(service.rules.isEmpty)
        let retry = await service.protect(assetIDs: ["a"])
        XCTAssertTrue(retry)
        XCTAssertNil(service.lastError)
        XCTAssertFalse(service.verdict(for: photo("a")).allowsRemoval)
    }

    func testProtectAssetsTakesEffectAndMirrorsRevision() async throws {
        let d = defaults()
        let (service, _) = try durableService(d)
        await service.load()
        var changes = 0
        service.onChange = { _ in changes += 1 }
        let start = service.revision
        let ok = await service.protect(assetIDs: ["a", "b"])
        XCTAssertTrue(ok)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(service.revision, start + 1)
        XCTAssertEqual(service.rules.count, 2)
        XCTAssertEqual(d.integer(forKey: ProtectionRuleService.lastRevisionKey), Int(service.revision))
        XCTAssertTrue(d.bool(forKey: ProtectionRuleService.everCreatedKey))
        if case .protected = service.verdict(for: photo("a")) {} else { XCTFail("a must be protected") }
        XCTAssertEqual(service.verdict(for: photo("c")), .unprotected)
        XCTAssertEqual(service.commitBlock(since: start), .ruleRevisionChanged)
        XCTAssertNil(service.commitBlock(since: service.revision))
    }

    func testDuplicateProtectKeepsOneRuleAndRevision() async throws {
        let (service, _) = try durableService(defaults())
        await service.load()
        _ = await service.protect(assetIDs: ["a"])
        let revision = service.revision
        let again = await service.protect(assetIDs: ["a"])
        XCTAssertTrue(again)
        XCTAssertEqual(service.rules.count, 1)
        XCTAssertEqual(service.revision, revision)
    }

    func testPendingWriteBlocksVerdictAndCommitUntilFinished() async throws {
        let (service, _) = try durableService(defaults())
        await service.load()
        var observed = false
        service.onChange = { [unowned service] _ in
            // onChange runs while the write is still pending.
            observed = true
            XCTAssertEqual(service.pendingWrites, 1)
            XCTAssertEqual(service.verdict(for: self.photo("zzz")), .indeterminate(.ruleWritePending))
            XCTAssertEqual(service.commitBlock(since: service.revision), .ruleWritePending)
        }
        _ = await service.protect(assetIDs: ["a"])
        XCTAssertTrue(observed)
        XCTAssertEqual(service.pendingWrites, 0)
        XCTAssertNil(service.commitBlock(since: service.revision))
    }

    func testRemoveRuleAndRemoveAll() async throws {
        let (service, _) = try durableService(defaults())
        await service.load()
        _ = await service.protect(assetIDs: ["a", "b"])
        let toRemove = try XCTUnwrap(service.rules.first)
        let start = service.revision
        let removed = await service.remove(ruleID: toRemove.id)
        XCTAssertTrue(removed)
        XCTAssertEqual(service.rules.count, 1)
        XCTAssertEqual(service.commitBlock(since: start), .ruleRevisionChanged, "a removal also invalidates an in-flight commit")
        let cleared = await service.removeAll()
        XCTAssertTrue(cleared)
        XCTAssertTrue(service.rules.isEmpty)
        XCTAssertEqual(service.verdict(for: photo("a")), .unprotected)
    }

    func testDateRangeProtectsInclusiveDay() async throws {
        let (service, _) = try durableService(defaults())
        await service.load()
        let day = try XCTUnwrap(LocalDay("2026-06-10"))
        let ok = await service.protect(range: day...day, timeZoneID: "UTC")
        XCTAssertTrue(ok)
        let noon = Date(timeIntervalSince1970: 1_781_092_800)   // 2026-06-10 12:00 UTC
        let lateNight = noon.addingTimeInterval(11.9 * 3600)
        let nextDay = noon.addingTimeInterval(12 * 3600)
        XCTAssertFalse(service.verdict(for: photo("x", at: noon.timeIntervalSince1970)).allowsRemoval)
        XCTAssertFalse(service.verdict(for: photo("x", at: lateNight.timeIntervalSince1970)).allowsRemoval)
        XCTAssertEqual(service.verdict(for: photo("x", at: nextDay.timeIntervalSince1970)), .unprotected)
        XCTAssertEqual(service.verdict(for: photo("x", at: nil)), .unprotected, "no date never matches a date rule")
    }

    func testRulesSurviveRelaunch() async throws {
        let d = defaults(); let path = tempPath()
        do {
            let (service, _) = try durableService(d, path: path)
            await service.load()
            _ = await service.protect(assetIDs: ["a"])
        }
        let (relaunched, _) = try durableService(d, path: path)
        await relaunched.load()
        XCTAssertEqual(relaunched.availability, .ready)
        XCTAssertFalse(relaunched.verdict(for: photo("a")).allowsRemoval)
    }

    func testAlbumRuleRowFailsClosedForEveryPhoto() async throws {
        let (service, store) = try durableService(defaults())
        try await store.debugExecute("INSERT INTO protection_rules(rule_id,kind,target_id,created_at,updated_at) VALUES('\(UUID().uuidString)','album','ALB',1,1)")
        await service.load()
        XCTAssertEqual(service.availability, .ready)
        // The App cannot yet resolve album membership, so every photo is indeterminate, never "unprotected".
        XCTAssertEqual(service.verdict(for: photo("a")), .indeterminate(.albumMembershipUnknown))
        XCTAssertTrue(service.decorated(photo("a")).record.flags.contains(.uncertainMetadata))
    }

    func testDecorationAddsHardFlagsWithoutMutatingStoredFlags() async throws {
        let (service, _) = try durableService(defaults())
        await service.load()
        _ = await service.protect(assetIDs: ["a"])
        let original = photo("a", flags: [.raw])
        let decorated = service.decorated(original)
        XCTAssertEqual(decorated.record.flags, [.raw, .userProtected])
        XCTAssertEqual(service.decoratedRecord(original), decorated.record)
        XCTAssertEqual(decorated.record.revision, original.record.revision)
        XCTAssertEqual(original.record.flags, [.raw])
        let other = photo("b", flags: [.raw])
        XCTAssertEqual(service.decorated(other), other, "unprotected photos are returned unchanged")
    }

    func testEditedAssetStaysProtected() async throws {
        let (service, _) = try durableService(defaults())
        await service.load()
        _ = await service.protect(assetIDs: ["a"])
        let edited = PhotoSnapshot(id: "a", record: AssetRecord(id: "a", revision: "r9-edited", flags: [.edited]),
                                   capturedAt: nil, burstID: nil, width: 10, height: 10)
        XCTAssertTrue(service.decorated(edited).record.flags.contains(.userProtected))
    }

    func testFlagOffStillEnforces() async throws {
        let (service, _) = try durableService(defaults())
        await service.load()
        _ = await service.protect(assetIDs: ["a"])
        #if DEBUG
        XCTAssertFalse(FeatureFlags.protectionRulesUI(arguments: ["-disableProtectionRulesUI"]))
        XCTAssertTrue(FeatureFlags.protectionRulesUI(arguments: []))
        #else
        XCTAssertFalse(FeatureFlags.protectionRulesUI(arguments: []))
        #endif
        XCTAssertFalse(service.verdict(for: photo("a")).allowsRemoval)
        XCTAssertTrue(service.decorated(photo("a")).record.flags.contains(.userProtected))
        XCTAssertNotNil(service.commitBlock(since: 0))
    }

    func testDecorationWhileUnavailableBlocksEverything() async throws {
        let gate = StaticProtectionGate()
        gate.availability = .unavailable("x")
        let decorated = gate.decorated(photo("a"))
        XCTAssertTrue(decorated.record.flags.contains(.uncertainMetadata))
        XCTAssertTrue(PreservationFlag.hard.contains(.uncertainMetadata))
    }

    func testStaticGateBehavesLikeTheRealOne() {
        let gate = StaticProtectionGate(protected: ["a"])
        XCTAssertTrue(gate.decorated(photo("a")).record.flags.contains(.userProtected))
        XCTAssertEqual(gate.decorated(photo("b")), photo("b"))
        gate.pendingWrites = 1
        XCTAssertEqual(gate.commitBlock(since: gate.revision), .ruleWritePending)
    }
}
