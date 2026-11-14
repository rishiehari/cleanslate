import XCTest
import SQLite3
import CleanSlateCore
@testable import CleanSlate

/// N05 C2: the protection tables, migration v1 -> v2 and the throwing rule CRUD.
final class ProtectionStoreTests: XCTestCase {
    private func tempPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("protection-\(UUID().uuidString).sqlite").path
    }
    private func cleanup(_ path: String) { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
    private func photo(_ id: String, at: Int64? = 1_000, flags: Set<PreservationFlag> = []) -> PhotoSnapshot {
        PhotoSnapshot(id: id, record: AssetRecord(id: id, revision: "r1", flags: flags),
                      capturedAt: at.map { Date(timeIntervalSince1970: TimeInterval($0)) }, burstID: nil,
                      width: 4032, height: 3024, originalFilename: "IMG.HEIC", isVideo: false, durationSeconds: 0, subtypes: 4)
    }
    private func assetRule(_ id: String) -> ProtectionRule { ProtectionRule(scope: .asset(localIdentifier: id), createdAt: Date(timeIntervalSince1970: 10)) }
    private func rangeRule(_ from: String, _ to: String, zone: String = "UTC") -> ProtectionRule {
        let start = LocalDay(from)!, end = LocalDay(to)!
        let interval = ProtectionDateResolver.interval(start: start, end: end, timeZoneID: zone)!
        return ProtectionRule(scope: .dateRange(start: start, end: end, timeZoneID: zone, startInclusive: interval.start, endExclusive: interval.endExclusive),
                              createdAt: Date(timeIntervalSince1970: 20))
    }

    /// Reads through a SEPARATE connection so the test sees what is really on disk.
    private func scalar(_ path: String, _ sql: String) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(st) }
        guard sqlite3_step(st) == SQLITE_ROW, sqlite3_column_type(st, 0) != SQLITE_NULL else { return nil }
        return String(cString: sqlite3_column_text(st, 0))
    }

    func testSchemaVersionIsDerivedFromMigrationsAndIsTwo() async throws {
        XCTAssertEqual(LibraryStore.schemaVersion, 2)
        let store = try LibraryStore(path: nil)
        let version = await store.userVersion
        XCTAssertEqual(version, 2)
    }

    func testFreshStoreHasEmptyRulesAtRevisionOne() async throws {
        let store = try LibraryStore(path: nil)
        let state = try await store.protectionRules()
        XCTAssertEqual(state.revision, 1)
        XCTAssertTrue(state.rules.isEmpty)
    }

    func testRulesRoundTripAndBumpRevision() async throws {
        let store = try LibraryStore(path: nil)
        let a = assetRule("A"), r = rangeRule("2026-06-10", "2026-06-12", zone: "America/New_York")
        let album = ProtectionRule(scope: .album(localIdentifier: "ALB"), createdAt: Date(timeIntervalSince1970: 30))
        let revision = try await store.insertProtectionRules([a, r, album])
        XCTAssertEqual(revision, 2)
        let state = try await store.protectionRules()
        XCTAssertEqual(state.revision, 2)
        XCTAssertEqual(Set(state.rules.map(\.id)), [a.id, r.id, album.id])
        XCTAssertEqual(state.rules.first { $0.id == r.id }, r)
        XCTAssertEqual(state.rules.first { $0.id == a.id }, a)
        XCTAssertEqual(state.rules.first { $0.id == album.id }, album)
    }

    func testDuplicateAssetRuleIdempotent() async throws {
        let store = try LibraryStore(path: nil)
        let first = try await store.insertProtectionRules([assetRule("A")])
        let second = try await store.insertProtectionRules([assetRule("A")])   // double tap: a new UUID, same target
        XCTAssertEqual(first, 2)
        XCTAssertEqual(second, 2, "no row changed, so the revision must not move")
        let state = try await store.protectionRules()
        XCTAssertEqual(state.rules.count, 1)
        XCTAssertEqual(state.revision, 2)
    }

    func testDuplicateRangeIsIgnored() async throws {
        let store = try LibraryStore(path: nil)
        _ = try await store.insertProtectionRules([rangeRule("2026-06-10", "2026-06-12")])
        let revision = try await store.insertProtectionRules([rangeRule("2026-06-10", "2026-06-12")])
        XCTAssertEqual(revision, 2)
        let count = try await store.protectionRules().rules.count
        XCTAssertEqual(count, 1)
    }

    func testDeleteBumpsRevisionOnlyWhenARowWasRemoved() async throws {
        let store = try LibraryStore(path: nil)
        let rule = assetRule("A")
        _ = try await store.insertProtectionRules([rule, assetRule("B")])
        let afterDelete = try await store.deleteProtectionRule(id: rule.id)
        XCTAssertEqual(afterDelete, 3)
        let afterMissing = try await store.deleteProtectionRule(id: rule.id)
        XCTAssertEqual(afterMissing, 3)
        let remaining = try await store.protectionRules().rules
        XCTAssertEqual(remaining.count, 1)
    }

    func testDeleteAllClearsRulesAndBumpsRevision() async throws {
        let store = try LibraryStore(path: nil)
        _ = try await store.insertProtectionRules([assetRule("A"), rangeRule("2026-01-01", "2026-01-02")])
        let revision = try await store.deleteAllProtectionRules()
        XCTAssertEqual(revision, 3)
        let state = try await store.protectionRules()
        XCTAssertTrue(state.rules.isEmpty)
        let again = try await store.deleteAllProtectionRules()
        XCTAssertEqual(again, 3, "nothing to delete, no bump")
    }

    func testEmptyInsertDoesNotBump() async throws {
        let store = try LibraryStore(path: nil)
        let revision = try await store.insertProtectionRules([])
        XCTAssertEqual(revision, 1)
    }

    func testMalformedRowFailsClosed() async throws {
        let store = try LibraryStore(path: nil)
        _ = try await store.insertProtectionRules([assetRule("A")])
        try await store.debugExecute("""
            INSERT INTO protection_rules(rule_id,kind,start_local_day,end_local_day,time_zone_id,start_utc,end_utc_exclusive,created_at,updated_at)
            VALUES('\(UUID().uuidString)','date_range','2026-13-45','2026-13-46','UTC',0,100,1,1)
            """)
        do {
            _ = try await store.protectionRules()
            XCTFail("a malformed row must make the whole read throw, not be skipped")
        } catch { /* expected */ }
    }

    func testMalformedRuleIDFailsClosed() async throws {
        let store = try LibraryStore(path: nil)
        try await store.debugExecute("INSERT INTO protection_rules(rule_id,kind,target_id,created_at,updated_at) VALUES('not-a-uuid','asset','A',1,1)")
        do { _ = try await store.protectionRules(); XCTFail("expected throw") } catch { /* expected */ }
    }

    func testSchemaRejectsInconsistentRows() async throws {
        let store = try LibraryStore(path: nil)
        // Asset rule without a target, and a range whose end precedes its start.
        do { try await store.debugExecute("INSERT INTO protection_rules(rule_id,kind,created_at,updated_at) VALUES('x','asset',1,1)"); XCTFail("expected CHECK failure") } catch {}
        do {
            try await store.debugExecute("""
                INSERT INTO protection_rules(rule_id,kind,start_local_day,end_local_day,time_zone_id,start_utc,end_utc_exclusive,created_at,updated_at)
                VALUES('y','date_range','2026-02-02','2026-02-01','UTC',0,100,1,1)
                """)
            XCTFail("expected CHECK failure")
        } catch {}
    }

    func testResetPreservesRules() async throws {
        let store = try LibraryStore(path: nil)
        _ = try await store.insertProtectionRules([assetRule("A"), rangeRule("2026-01-01", "2026-01-02")])
        try await store.upsert([photo("A")])
        try await store.reset()
        let assets = await store.assetCount()
        let state = try await store.protectionRules()
        XCTAssertEqual(assets, 0)
        XCTAssertEqual(state.rules.count, 2)
        XCTAssertEqual(state.revision, 2)
    }

    func testUpsertStripsUserProtectedFlag() async throws {
        let store = try LibraryStore(path: nil)
        try await store.upsert([photo("A", flags: [.userProtected, .favorite])])
        let loaded = await store.snapshots(ids: ["A"])
        XCTAssertEqual(loaded["A"]?.record.flags, [.favorite])
        try await store.debugExecute("UPDATE assets SET flags = flags || ',userProtected' WHERE id='A'")
        // Even if a row somehow carried it, a fresh upsert rewrites the column without it.
        try await store.upsert([photo("A", flags: [.userProtected])])
        let again = await store.snapshots(ids: ["A"])
        XCTAssertEqual(again["A"]?.record.flags, [])
    }

    func testEditedAssetStaysProtected() async throws {
        let store = try LibraryStore(path: nil)
        _ = try await store.insertProtectionRules([assetRule("A")])
        try await store.upsert([photo("A")])
        let edited = PhotoSnapshot(id: "A", record: AssetRecord(id: "A", revision: "r2-edited", flags: [.edited]),
                                   capturedAt: Date(timeIntervalSince1970: 1_000), burstID: nil, width: 4032, height: 3024,
                                   originalFilename: "IMG.HEIC", isVideo: false, durationSeconds: 0, subtypes: 4)
        try await store.upsert([edited])
        let state = try await store.protectionRules()
        let set = try ProtectionRuleSet(rules: state.rules, revision: state.revision)
        XCTAssertFalse(set.verdict(ProtectionSubject(id: "A", capturedAt: edited.capturedAt)).allowsRemoval)
    }

    func testProtectedRangeIndexedCount() async throws {
        let store = try LibraryStore(path: nil)
        try await store.upsert([photo("a", at: 100), photo("b", at: 199), photo("c", at: 200), photo("d", at: nil), photo("e", at: 150)])
        try await store.markDeleted(["e"])
        let count = await store.protectedRangeIndexedCount(start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(count, 2, "half-open [start, end), skips deleted and undated rows")
    }

    func testMigrationFromV1PreservesRowsAndCreatesProtectionTables() async throws {
        let path = tempPath(); defer { cleanup(path) }
        do {
            let v1 = try LibraryStore(path: path, maximumVersion: 1)
            let v1Version = await v1.userVersion
            XCTAssertEqual(v1Version, 1)
            try await v1.upsert([photo("a"), photo("b", at: 2_000, flags: [.favorite])])
            try await v1.putFeatures([("a", "r1", 0xABCD)], version: 2)
            try await v1.setMeta("scan.offset", Data("500".utf8))
            try await v1.addReceipt(id: "r", createdAt: Date(timeIntervalSince1970: 5), json: "{\"x\":1}")
            try await v1.debugExecute("INSERT INTO digests(asset_id,revision,signature,logical_bytes,verified_at) VALUES('a','r1','sig',123,1)")
            let hasTable = scalar(path, "SELECT name FROM sqlite_master WHERE name='protection_rules'")
            XCTAssertNil(hasTable, "a v1 database has no protection table")
        }
        let v2 = try LibraryStore(path: path)
        let version = await v2.userVersion
        XCTAssertEqual(version, 2)
        let loaded = await v2.snapshots(ids: ["a", "b"])
        XCTAssertEqual(loaded["a"], photo("a"))
        XCTAssertEqual(loaded["b"], photo("b", at: 2_000, flags: [.favorite]))
        let offset = await v2.meta("scan.offset")
        XCTAssertEqual(offset.flatMap { String(data: $0, encoding: .utf8) }, "500")
        let receipts = await v2.receiptJSONs()
        XCTAssertEqual(receipts, ["{\"x\":1}"])
        let hash = await v2.dhash(id: "a", revision: "r1")
        XCTAssertEqual(hash, 0xABCD)
        let state = try await v2.protectionRules()
        XCTAssertEqual(state.revision, 1)
        XCTAssertTrue(state.rules.isEmpty)
        XCTAssertEqual(scalar(path, "PRAGMA integrity_check"), "ok")
        XCTAssertEqual(scalar(path, "PRAGMA user_version"), "2")
        XCTAssertEqual(scalar(path, "SELECT COUNT(*) FROM digests"), "1")
        XCTAssertEqual(scalar(path, "SELECT revision FROM protection_rule_revision"), "1")
    }

    func testRulesSurviveReopen() async throws {
        let path = tempPath(); defer { cleanup(path) }
        let rule = assetRule("A")
        do {
            let store = try LibraryStore(path: path)
            _ = try await store.insertProtectionRules([rule])
        }
        let reopened = try LibraryStore(path: path)
        let state = try await reopened.protectionRules()
        XCTAssertEqual(state.rules, [rule])
        XCTAssertEqual(state.revision, 2)
    }

    func testV2DatabaseOpenedWithV1MigrationListIsUntouched() async throws {
        let path = tempPath(); defer { cleanup(path) }
        let rule = assetRule("A")
        do {
            let store = try LibraryStore(path: path)
            _ = try await store.insertProtectionRules([rule])
        }
        // An older binary only knows migration 1; it must neither throw nor downgrade the file.
        let older = try LibraryStore(path: path, maximumVersion: 1)
        let version = await older.userVersion
        XCTAssertEqual(version, 2)
        XCTAssertEqual(scalar(path, "PRAGMA user_version"), "2")
        let state = try await LibraryStore(path: path).protectionRules()
        XCTAssertEqual(state.rules, [rule])
    }

    func testFailedWriteLeavesRulesAndRevisionUntouched() async throws {
        let store = try LibraryStore(path: nil)
        _ = try await store.insertProtectionRules([assetRule("A")])
        await store.debugFailNextProtectionWrite()
        do { _ = try await store.insertProtectionRules([assetRule("B")]); XCTFail("expected injected failure") } catch {}
        let state = try await store.protectionRules()
        XCTAssertEqual(state.revision, 2)
        XCTAssertEqual(state.rules.count, 1)
        // The injection is one-shot.
        let revision = try await store.insertProtectionRules([assetRule("B")])
        XCTAssertEqual(revision, 3)
    }

    func testBatchInsertIsAtomic() async throws {
        let store = try LibraryStore(path: nil)
        let bad = ProtectionRule(scope: .dateRange(start: LocalDay("2026-01-02")!, end: LocalDay("2026-01-01")!, timeZoneID: "UTC",
                                                   startInclusive: Date(timeIntervalSince1970: 0), endExclusive: Date(timeIntervalSince1970: 10)))
        do { _ = try await store.insertProtectionRules([assetRule("A"), bad]); XCTFail("CHECK constraint must reject") } catch {}
        let state = try await store.protectionRules()
        XCTAssertTrue(state.rules.isEmpty, "the first row must roll back with the failing one")
        XCTAssertEqual(state.revision, 1)
    }
}
