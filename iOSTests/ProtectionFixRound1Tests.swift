import XCTest
import CleanSlateCore
@testable import CleanSlate

/// N05 fix round 1 (validator findings B1, M1, M2, m2, m5) for the rule service and store.
@MainActor
final class ProtectionFixRound1Tests: XCTestCase {
    private var suites: [String] = []
    private var paths: [String] = []

    override func tearDown() async throws {
        for suite in suites { UserDefaults().removePersistentDomain(forName: suite) }
        for path in paths { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        suites = []; paths = []
    }

    private func defaults() -> UserDefaults {
        let name = "org.cleanslate.test.fix1.\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }
    private func tempPath() -> String {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("fix1-\(UUID().uuidString).sqlite").path
        paths.append(path)
        return path
    }
    private func photo(_ id: String, at: TimeInterval? = 1_000) -> PhotoSnapshot {
        PhotoSnapshot(id: id, record: AssetRecord(id: id, revision: "r1"), capturedAt: at.map { Date(timeIntervalSince1970: $0) },
                      burstID: nil, width: 10, height: 10)
    }
    private func rig(_ d: UserDefaults? = nil, path: String? = nil) throws -> (ProtectionRuleService, LibraryStore) {
        let store = try LibraryStore(path: path ?? tempPath())
        return (ProtectionRuleService(store: store, defaults: d ?? defaults()), store)
    }

    // MARK: B1

    func testOverLimitAssetRulesRefusedBeforeAnyRowIsWritten() async throws {
        let (service, store) = try rig()
        await service.load()
        _ = await service.protect(assetIDs: ["keep"])
        let before = try await store.protectionRules()
        let ok = await service.protect(assetIDs: (0...ProtectionRuleSet.maximumAssetRules).map { "x\($0)" })
        XCTAssertFalse(ok)
        XCTAssertNotNil(service.lastError)
        let after = try await store.protectionRules()
        XCTAssertEqual(after.rules.count, 1, "zero rows were written")
        XCTAssertEqual(after.revision, before.revision)
        XCTAssertEqual(service.availability, .ready)
        XCTAssertFalse(service.verdict(for: photo("keep")).allowsRemoval, "existing protection is untouched")
    }

    func testOverLimitDateRulesRefusedBeforeAnyRowIsWritten() async throws {
        let (service, store) = try rig()
        await service.load()
        for i in 0..<ProtectionRuleSet.maximumDateRules {
            let day = try XCTUnwrap(LocalDay(year: 2000 + i / 12, month: i % 12 + 1, day: 1))
            let ok = await service.protect(range: day...day, timeZoneID: "UTC")
            XCTAssertTrue(ok, "rule \(i)")
        }
        let before = try await store.protectionRules()
        let extra = try XCTUnwrap(LocalDay("2020-05-05"))
        let refused = await service.protect(range: extra...extra, timeZoneID: "UTC")
        XCTAssertFalse(refused)
        let after = try await store.protectionRules()
        XCTAssertEqual(after.rules.count, ProtectionRuleSet.maximumDateRules)
        XCTAssertEqual(after.revision, before.revision)
        XCTAssertEqual(service.availability, .ready)
        XCTAssertEqual(service.rules.count, ProtectionRuleSet.maximumDateRules)
    }

    func testPostCommitRebuildFailureIsUnavailable() async throws {
        let (service, store) = try rig()
        await service.load()
        #if DEBUG
        service.debugFailNextRebuild = true
        #endif
        let ok = await service.protect(assetIDs: ["a"])
        XCTAssertFalse(ok)
        guard case .unavailable = service.availability else { return XCTFail("a committed write that cannot be reloaded must fail closed, got \(service.availability)") }
        XCTAssertFalse(service.verdict(for: photo("a")).allowsRemoval)
        XCTAssertFalse(service.verdict(for: photo("never-protected")).allowsRemoval)
        XCTAssertNotNil(service.commitBlock(since: service.revision))
        XCTAssertFalse(service.lastError?.contains("Nothing was changed") ?? false, "the row WAS committed")
        let stored = try await store.protectionRules()
        XCTAssertEqual(stored.rules.count, 1)
        // A retry loads it again.
        await service.load()
        XCTAssertEqual(service.availability, .ready)
        XCTAssertFalse(service.verdict(for: photo("a")).allowsRemoval)
    }

    // MARK: M1

    func testRemoveAllowedWhenSetIsMalformedButStoreReadable() async throws {
        let (service, store) = try rig()
        await service.load()
        _ = await service.protect(assetIDs: ["a"])
        try await store.debugExecute("""
            INSERT INTO protection_rules(rule_id,kind,start_local_day,end_local_day,time_zone_id,start_utc,end_utc_exclusive,created_at,updated_at)
            VALUES('\(UUID().uuidString)','date_range','2026-13-45','2026-13-46','UTC',0,100,1,1)
            """)
        await service.load()
        guard case .unavailable = service.availability else { return XCTFail("expected unavailable, got \(service.availability)") }
        let cleared = await service.removeAll()
        XCTAssertTrue(cleared, "the user can always get out of a broken rule set")
        XCTAssertEqual(service.availability, .ready)
        XCTAssertTrue(service.rules.isEmpty)
        XCTAssertEqual(service.verdict(for: photo("a")), .unprotected)
    }

    func testRemoveOneRuleAllowedWhenSetIsOverLimit() async throws {
        let (service, store) = try rig()
        await service.load()
        let count = ProtectionRuleSet.maximumAssetRules + 1
        try await store.debugExecute("""
            WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<\(count))
            INSERT INTO protection_rules(rule_id,kind,target_id,created_at,updated_at)
            SELECT upper(hex(randomblob(4)))||'-0000-4000-8000-'||upper(hex(randomblob(6))),'asset','A'||i,i,i FROM n
            """)
        await service.load()
        guard case .unavailable = service.availability else { return XCTFail("expected unavailable, got \(service.availability)") }
        XCTAssertEqual(service.rules.count, count, "the rules are still listed so the user can pick one to remove")
        let first = try XCTUnwrap(service.rules.first)
        let removed = await service.remove(ruleID: first.id)
        XCTAssertTrue(removed)
        XCTAssertEqual(service.availability, .ready)
        XCTAssertEqual(service.rules.count, count - 1)
    }

    // MARK: M2

    func testRevisionRowMissingWithRulesIsUnavailableWithoutDefaults() async throws {
        let path = tempPath()
        let (first, store) = try rig(path: path)
        await first.load()
        _ = await first.protect(assetIDs: ["a"])
        try await store.debugExecute("DELETE FROM protection_rule_revision")
        let (second, _) = try rig(path: path)                 // fresh UserDefaults: no "ever created" memory
        await second.load()
        guard case .unavailable = second.availability else { return XCTFail("expected unavailable, got \(second.availability)") }
        XCTAssertFalse(second.verdict(for: photo("a")).allowsRemoval)
        XCTAssertFalse(second.verdict(for: photo("other")).allowsRemoval)
    }

    func testFallbackWithOnDiskRulesIsUnavailableWithoutDefaults() async throws {
        let path = tempPath()
        let (first, _) = try rig(path: path)
        await first.load()
        _ = await first.protect(assetIDs: ["a"])
        // The app could not open its database and fell back to memory; UserDefaults forgot everything.
        let fallback = ProtectionRuleService(store: try LibraryStore(path: nil), defaults: defaults(), onDiskDatabasePath: path)
        await fallback.load()
        guard case .unavailable = fallback.availability else { return XCTFail("expected unavailable, got \(fallback.availability)") }
        XCTAssertNotNil(fallback.commitBlock(since: fallback.revision))
        // No database file at all: a genuinely fresh install is fine.
        let fresh = ProtectionRuleService(store: try LibraryStore(path: nil), defaults: defaults(), onDiskDatabasePath: tempPath())
        await fresh.load()
        XCTAssertEqual(fresh.availability, .ready)
    }

    func testRulesOnDiskWithFreshDefaultsLoadAndRestoreTheSentinel() async throws {
        let path = tempPath()
        let (first, _) = try rig(path: path)
        await first.load()
        _ = await first.protect(assetIDs: ["a"])
        let d = defaults()
        let (second, _) = try rig(d, path: path)
        await second.load()
        XCTAssertEqual(second.availability, .ready)
        XCTAssertFalse(second.verdict(for: photo("a")).allowsRemoval)
        XCTAssertTrue(d.bool(forKey: ProtectionRuleService.everCreatedKey), "the defaults sentinel is rebuilt from the database")
        XCTAssertEqual(d.integer(forKey: ProtectionRuleService.lastRevisionKey), Int(second.revision))
    }

    // MARK: m5

    func testConcurrentWritesPublishTheNewestRevision() async throws {
        let d = defaults()
        let (service, store) = try rig(d)
        await service.load()
        async let a = service.protect(assetIDs: ["a"])
        async let b = service.protect(assetIDs: ["b"])
        async let c = service.protect(assetIDs: ["c"])
        let results = await [a, b, c]
        XCTAssertEqual(results, [true, true, true])
        let stored = try await store.protectionRules()
        XCTAssertEqual(service.revision, stored.revision)
        XCTAssertEqual(service.rules.count, 3)
        XCTAssertEqual(d.integer(forKey: ProtectionRuleService.lastRevisionKey), Int(stored.revision))
        XCTAssertEqual(service.pendingWrites, 0)
        for id in ["a", "b", "c"] { XCTAssertFalse(service.verdict(for: photo(id)).allowsRemoval) }
    }
}

/// m2: the store itself refuses rules it could never evaluate.
final class ProtectionStoreFixRound1Tests: XCTestCase {
    func testEmptyAssetIDRejectedByStore() async throws {
        let store = try LibraryStore(path: nil)
        for scope in [ProtectionScope.asset(localIdentifier: ""), .album(localIdentifier: "")] {
            do { _ = try await store.insertProtectionRules([ProtectionRule(scope: scope)]); XCTFail("empty target must be rejected: \(scope)") } catch {}
        }
        let state = try await store.protectionRules()
        XCTAssertTrue(state.rules.isEmpty)
        XCTAssertEqual(state.revision, 1)
    }
}
