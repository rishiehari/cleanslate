import Foundation
import SQLite3
import CleanSlateCore

/// The persistent, rebuildable library index. One SQLite connection owned by this actor.
/// Holds metadata and derived fingerprints only: no photos, thumbnails or faces.
/// (WAL, foreign keys on, versioned migrations, data protection, excluded from backup.)
actor LibraryStore {
    /// Derived from the migration list so a new migration can never be forgotten here.
    static var schemaVersion: Int { migrations.count }

    enum StoreError: Error { case open(String), sql(String), malformedProtectionRule(String), protectionRevisionMissing }

    // Only touched by this actor (and its deinit, which has exclusive access).
    nonisolated(unsafe) private var db: OpaquePointer?
    let path: String?

    /// `path == nil` opens an in-memory database (tests).
    /// `maximumVersion` limits which migrations run. It exists only so tests can build a v1 database and
    /// simulate an older binary opening a newer file; production always passes nil.
    init(path: String?, maximumVersion: Int? = nil) throws {
        self.path = path
        var handle: OpaquePointer?
        let target = path ?? ":memory:"
        guard sqlite3_open_v2(target, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            throw StoreError.open(message)
        }
        db = handle
        try Self.exec(handle, "PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA synchronous=NORMAL;")
        try Self.migrate(handle, upTo: maximumVersion)
        if let path {
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: path)
            var url = URL(fileURLWithPath: path)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
    }

    deinit { sqlite3_close(db) }

    static func defaultPath() -> String? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        else { return nil }
        return dir.appendingPathComponent("library-index.sqlite").path
    }

    // MARK: Migrations (ordered; each step runs once)

    private static let migrations: [String] = [
        // v1
        """
        CREATE TABLE meta(key TEXT PRIMARY KEY, value BLOB);
        CREATE TABLE assets(
          id TEXT PRIMARY KEY, revision TEXT NOT NULL, media_type INTEGER NOT NULL, subtypes INTEGER NOT NULL DEFAULT 0,
          width INTEGER NOT NULL, height INTEGER NOT NULL, created_s INTEGER, duration_ms INTEGER NOT NULL DEFAULT 0,
          burst_id TEXT, flags TEXT NOT NULL DEFAULT '', original_filename TEXT,
          inventoried_at REAL NOT NULL, deleted INTEGER NOT NULL DEFAULT 0);
        CREATE INDEX assets_exact ON assets(media_type, width, height, created_s) WHERE deleted = 0;
        CREATE INDEX assets_time ON assets(created_s) WHERE deleted = 0;
        CREATE INDEX assets_burst ON assets(burst_id) WHERE burst_id IS NOT NULL AND deleted = 0;
        CREATE TABLE features(
          asset_id TEXT PRIMARY KEY REFERENCES assets(id) ON DELETE CASCADE, revision TEXT NOT NULL,
          dhash INTEGER NOT NULL, band0 INTEGER NOT NULL, band1 INTEGER NOT NULL, band2 INTEGER NOT NULL, band3 INTEGER NOT NULL,
          feature_version INTEGER NOT NULL);
        CREATE INDEX f_b0 ON features(band0); CREATE INDEX f_b1 ON features(band1);
        CREATE INDEX f_b2 ON features(band2); CREATE INDEX f_b3 ON features(band3);
        CREATE TABLE digests(
          asset_id TEXT PRIMARY KEY REFERENCES assets(id) ON DELETE CASCADE, revision TEXT NOT NULL,
          signature TEXT NOT NULL, logical_bytes INTEGER NOT NULL, verified_at REAL NOT NULL);
        CREATE INDEX digests_sig ON digests(signature);
        CREATE TABLE groups(id TEXT PRIMARY KEY, kind INTEGER NOT NULL, state INTEGER NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL);
        CREATE TABLE group_members(group_id TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE, asset_id TEXT NOT NULL,
          role INTEGER NOT NULL, revision_at_grouping TEXT NOT NULL, PRIMARY KEY(group_id, asset_id));
        CREATE INDEX gm_asset ON group_members(asset_id);
        CREATE TABLE reviews(group_id TEXT PRIMARY KEY, decision INTEGER NOT NULL, decided_at REAL NOT NULL, member_revisions TEXT NOT NULL);
        CREATE TABLE receipts(id TEXT PRIMARY KEY, created_at REAL NOT NULL, payload_json TEXT NOT NULL);
        """,
        // v2 (N05): user protection rules. User intent, never derived data: reset() must not touch these tables.
        """
        CREATE TABLE protection_rules(
          rule_id TEXT PRIMARY KEY,
          kind TEXT NOT NULL CHECK(kind IN ('asset','album','date_range')),
          target_id TEXT,
          start_local_day TEXT, end_local_day TEXT,
          calendar_id TEXT NOT NULL DEFAULT 'gregorian', time_zone_id TEXT,
          start_utc REAL, end_utc_exclusive REAL,
          created_at REAL NOT NULL, updated_at REAL NOT NULL,
          enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0,1)),
          rule_version INTEGER NOT NULL DEFAULT 1,
          CHECK((kind IN ('asset','album') AND target_id IS NOT NULL AND start_local_day IS NULL) OR
                (kind='date_range' AND target_id IS NULL AND start_local_day IS NOT NULL AND end_local_day IS NOT NULL
                 AND time_zone_id IS NOT NULL AND start_utc IS NOT NULL AND end_utc_exclusive IS NOT NULL
                 AND end_utc_exclusive > start_utc AND end_local_day >= start_local_day)));
        CREATE UNIQUE INDEX protection_unique_target ON protection_rules(kind, target_id) WHERE target_id IS NOT NULL;
        CREATE UNIQUE INDEX protection_unique_range ON protection_rules(start_local_day, end_local_day, time_zone_id) WHERE kind='date_range';
        CREATE TABLE protection_rule_revision(singleton INTEGER PRIMARY KEY CHECK(singleton=1), revision INTEGER NOT NULL);
        INSERT INTO protection_rule_revision VALUES (1,1);
        """
    ]

    private static func migrate(_ db: OpaquePointer?, upTo maximumVersion: Int?) throws {
        let target = min(migrations.count, maximumVersion ?? migrations.count)
        var current = 0
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW {
            current = Int(sqlite3_column_int(statement, 0))
        }
        sqlite3_finalize(statement)
        guard current < target else { return }
        for version in current..<target {
            try exec(db, "BEGIN IMMEDIATE;")
            do {
                try exec(db, migrations[version])
                try exec(db, "PRAGMA user_version = \(version + 1);")
                try exec(db, "COMMIT;")
            } catch {
                try? exec(db, "ROLLBACK;")
                throw error
            }
        }
    }

    // MARK: Plumbing

    private static func exec(_ db: OpaquePointer?, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw StoreError.sql(message)
        }
    }

    private func run(_ sql: String, _ bind: (OpaquePointer?) -> Void = { _ in }) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.sql(String(cString: sqlite3_errmsg(db))) }
        defer { sqlite3_finalize(statement) }
        bind(statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else { throw StoreError.sql(String(cString: sqlite3_errmsg(db))) }
    }

    private func rows<T>(_ sql: String, bind: (OpaquePointer?) -> Void = { _ in }, map: (OpaquePointer?) -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.sql(String(cString: sqlite3_errmsg(db))) }
        defer { sqlite3_finalize(statement) }
        bind(statement)
        var out: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW { out.append(map(statement)) }
        return out
    }

    private func transaction(_ body: () throws -> Void) throws {
        try Self.exec(db, "BEGIN IMMEDIATE;")
        do { try body(); try Self.exec(db, "COMMIT;") } catch { try? Self.exec(db, "ROLLBACK;"); throw error }
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private func text(_ s: OpaquePointer?, _ i: Int32, _ v: String?) {
        if let v { sqlite3_bind_text(s, i, v, -1, Self.transient) } else { sqlite3_bind_null(s, i) }
    }
    private func str(_ s: OpaquePointer?, _ i: Int32) -> String? {
        sqlite3_column_type(s, i) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(s, i))
    }

    // MARK: Meta

    var userVersion: Int { (try? rows("PRAGMA user_version", map: { Int(sqlite3_column_int($0, 0)) }).first) ?? 0 }

    func meta(_ key: String) -> Data? {
        (try? rows("SELECT value FROM meta WHERE key=?", bind: { text($0, 1, key) }) { s -> Data? in
            guard let bytes = sqlite3_column_blob(s, 0) else { return nil }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(s, 0)))
        }.first ?? nil)
    }

    func setMeta(_ key: String, _ value: Data?) throws {
        if let value {
            try run("INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value") { s in
                text(s, 1, key); _ = value.withUnsafeBytes { sqlite3_bind_blob(s, 2, $0.baseAddress, Int32(value.count), Self.transient) }
            }
        } else {
            try run("DELETE FROM meta WHERE key=?") { text($0, 1, key) }
        }
    }

    // MARK: Assets

    /// Inserts or updates in ONE transaction. A changed revision drops stale features and digests.
    func upsert(_ snapshots: [PhotoSnapshot]) throws {
        try transaction {
            let now = Date().timeIntervalSince1970
            for photo in snapshots {
                try run("DELETE FROM features WHERE asset_id=? AND revision<>?") { text($0, 1, photo.id); text($0, 2, photo.record.revision) }
                try run("DELETE FROM digests WHERE asset_id=? AND revision<>?") { text($0, 1, photo.id); text($0, 2, photo.record.revision) }
                try run("""
                    INSERT INTO assets(id,revision,media_type,subtypes,width,height,created_s,duration_ms,burst_id,flags,original_filename,inventoried_at,deleted)
                    VALUES(?,?,?,?,?,?,?,?,?,?,?,?,0)
                    ON CONFLICT(id) DO UPDATE SET revision=excluded.revision, media_type=excluded.media_type, subtypes=excluded.subtypes,
                      width=excluded.width, height=excluded.height, created_s=excluded.created_s, duration_ms=excluded.duration_ms,
                      burst_id=excluded.burst_id, flags=excluded.flags, original_filename=excluded.original_filename,
                      inventoried_at=excluded.inventoried_at, deleted=0
                    """) { s in
                    text(s, 1, photo.id); text(s, 2, photo.record.revision)
                    sqlite3_bind_int(s, 3, photo.isVideo ? 2 : 1); sqlite3_bind_int64(s, 4, Int64(photo.subtypes))
                    sqlite3_bind_int(s, 5, Int32(photo.width)); sqlite3_bind_int(s, 6, Int32(photo.height))
                    if let date = photo.capturedAt { sqlite3_bind_int64(s, 7, Int64(date.timeIntervalSince1970)) } else { sqlite3_bind_null(s, 7) }
                    sqlite3_bind_int64(s, 8, Int64(photo.durationSeconds * 1000))
                    text(s, 9, photo.burstID)
                    text(s, 10, photo.record.flags.subtracting([.userProtected]).map(\.rawValue).sorted().joined(separator: ","))
                    text(s, 11, photo.originalFilename)
                    sqlite3_bind_double(s, 12, now)
                }
            }
        }
    }

    func markDeleted(_ ids: [String]) throws {
        try transaction { for id in ids { try run("UPDATE assets SET deleted=1 WHERE id=?") { text($0, 1, id) } } }
    }

    /// Deactivates index rows not seen during this inventory. Scoped scans use this to exclude
    /// out-of-scope rows from analysis. This is index membership, never proof of a Photos deletion.
    @discardableResult
    func markUnseen(before startedAt: Double) throws -> Int {
        let before = assetCount()
        try run("UPDATE assets SET deleted=1 WHERE deleted=0 AND inventoried_at < ?") { sqlite3_bind_double($0, 1, startedAt) }
        return before - assetCount()
    }

    /// Screenshots and videos without any protection flag (candidates for the keeper-less lists).
    func standaloneCandidates(limit: Int) -> [PhotoSnapshot] {
        (try? rows("""
            SELECT \(Self.assetColumns) FROM assets WHERE deleted=0 AND flags='' AND (media_type=2 OR (subtypes & 4)<>0)
            ORDER BY created_s DESC LIMIT ?
            """, bind: { sqlite3_bind_int($0, 1, Int32(limit)) }, map: { snapshot(from: $0) })) ?? []
    }

    func assetCount() -> Int {
        (try? rows("SELECT COUNT(*) FROM assets WHERE deleted=0", map: { Int(sqlite3_column_int64($0, 0)) }).first) ?? 0
    }

    private static let assetColumns = "id,revision,media_type,subtypes,width,height,created_s,duration_ms,burst_id,flags,original_filename"

    private func snapshot(from s: OpaquePointer?) -> PhotoSnapshot {
        let id = String(cString: sqlite3_column_text(s, 0))
        let flags = Set((str(s, 9) ?? "").split(separator: ",").compactMap { PreservationFlag(rawValue: String($0)) })
        let record = AssetRecord(id: id, revision: String(cString: sqlite3_column_text(s, 1)), flags: flags)
        let created: Date? = sqlite3_column_type(s, 6) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(s, 6)))
        return PhotoSnapshot(id: id, record: record, capturedAt: created, burstID: str(s, 8),
                             width: Int(sqlite3_column_int(s, 4)), height: Int(sqlite3_column_int(s, 5)),
                             originalFilename: str(s, 10), isVideo: sqlite3_column_int(s, 2) == 2,
                             durationSeconds: Double(sqlite3_column_int64(s, 7)) / 1000, subtypes: UInt(sqlite3_column_int64(s, 3)))
    }

    func snapshots(ids: [String]) -> [String: PhotoSnapshot] {
        var out: [String: PhotoSnapshot] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
            let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let found = (try? rows("SELECT \(Self.assetColumns) FROM assets WHERE deleted=0 AND id IN (\(marks))",
                                   bind: { s in for (i, id) in chunk.enumerated() { text(s, Int32(i + 1), id) } },
                                   map: { snapshot(from: $0) })) ?? []
            for photo in found { out[photo.id] = photo }
        }
        return out
    }

    /// Newest first, paged. Used by the scan to walk the library without holding it all in memory.
    func page(offset: Int, limit: Int) -> [PhotoSnapshot] {
        (try? rows("SELECT \(Self.assetColumns) FROM assets WHERE deleted=0 ORDER BY created_s DESC, id LIMIT ? OFFSET ?",
                   bind: { sqlite3_bind_int($0, 1, Int32(limit)); sqlite3_bind_int($0, 2, Int32(offset)) },
                   map: { snapshot(from: $0) })) ?? []
    }

    /// Cheap metadata for exact-copy bucketing (every live asset).
    func exactKeys() -> [ExactKey] {
        (try? rows("SELECT id,media_type,width,height,created_s,duration_ms,original_filename FROM assets WHERE deleted=0") { s in
            ExactKey(id: String(cString: sqlite3_column_text(s, 0)), mediaType: Int(sqlite3_column_int(s, 1)),
                     pixelWidth: Int(sqlite3_column_int(s, 2)), pixelHeight: Int(sqlite3_column_int(s, 3)),
                     creationSecond: sqlite3_column_type(s, 4) == SQLITE_NULL ? nil : sqlite3_column_int64(s, 4),
                     durationMillis: sqlite3_column_int64(s, 5), originalFilename: str(s, 6))
        }) ?? []
    }

    // MARK: Keyset-paged twins of the whole-library queries (F03: no whole-library arrays).
    // The old APIs stay alongside for rollback; new code pages with `afterRowID`/`afterTime` cursors.

    private static let exactKeyColumns = "id,media_type,width,height,created_s,duration_ms,original_filename"

    /// Next page of exact keys after a rowid cursor (keyset: same cost no matter how much was done).
    func exactKeyPage(afterRowID: Int64, limit: Int) -> (keys: [ExactKey], lastRowID: Int64) {
        var last = afterRowID
        let keys = (try? rows("""
            SELECT rowid, \(Self.exactKeyColumns) FROM assets WHERE deleted=0 AND rowid > ?
            ORDER BY rowid LIMIT ?
            """, bind: { sqlite3_bind_int64($0, 1, afterRowID); sqlite3_bind_int($0, 2, Int32(limit)) },
                               map: { s -> ExactKey in last = max(last, sqlite3_column_int64(s, 0)); return exactKey(from: s, offset: 1) })) ?? []
        return (keys, last)
    }

    private func exactKey(from s: OpaquePointer?, offset: Int32) -> ExactKey {
        ExactKey(id: String(cString: sqlite3_column_text(s, offset)), mediaType: Int(sqlite3_column_int(s, offset + 1)),
                 pixelWidth: Int(sqlite3_column_int(s, offset + 2)), pixelHeight: Int(sqlite3_column_int(s, offset + 3)),
                 creationSecond: sqlite3_column_type(s, offset + 4) == SQLITE_NULL ? nil : sqlite3_column_int64(s, offset + 4),
                 durationMillis: sqlite3_column_int64(s, offset + 5), originalFilename: str(s, offset + 6))
    }

    /// Next page of sequence items in `byTimeThenID` order (NULL created_s sorts first, matching
    /// SequenceGrouping). Pass `afterTime: nil, afterID: ""` for the first page.
    func sequencePage(afterTime: Int64?, afterID: String, limit: Int, version: Int = 2) -> (items: [SequenceItem], lastTime: Int64?, lastID: String) {
        let minTime = Int64.min
        let order = "COALESCE(created_s, \(minTime)), id"
        let paging = afterTime == nil && afterID.isEmpty ? "" : """
            AND (COALESCE(created_s, \(minTime)) > ? OR (COALESCE(created_s, \(minTime)) = ? AND id > ?))
            """
        var items: [SequenceItem] = []
        var lastTime: Int64? = afterTime
        var lastID = afterID
        let found = (try? rows("""
            SELECT id, created_s, burst_id, f.dhash FROM assets a
              LEFT JOIN features f ON f.asset_id=a.id AND f.revision=a.revision AND f.feature_version=?
            WHERE a.deleted=0 AND a.media_type=1 \(paging)
            ORDER BY \(order) LIMIT ?
            """, bind: { s in
                sqlite3_bind_int(s, 1, Int32(version))
                if !paging.isEmpty {
                    let t = afterTime ?? minTime
                    sqlite3_bind_int64(s, 2, t); sqlite3_bind_int64(s, 3, t); text(s, 4, afterID)
                    sqlite3_bind_int(s, 5, Int32(limit))
                } else {
                    sqlite3_bind_int(s, 2, Int32(limit))
                }
            }, map: { s -> SequenceItem? in
                guard let id = sqlite3_column_text(s, 0).map({ String(cString: $0) }) else { return nil }
                lastTime = sqlite3_column_type(s, 1) == SQLITE_NULL ? nil : sqlite3_column_int64(s, 1)
                lastID = id
                return SequenceItem(id: id, timeSeconds: lastTime, burstID: str(s, 2),
                                    hash: sqlite3_column_type(s, 3) == SQLITE_NULL ? nil : UInt64(bitPattern: sqlite3_column_int64(s, 3)))
            })) ?? []
        items = found.compactMap { $0 }
        return (items, lastTime, lastID)
    }



    // MARK: Features (difference hash + LSH bands)

    /// Next batch of images that still need a fingerprint, resuming AFTER `afterRowID` (a keyset cursor), so each
    /// batch costs the same no matter how many were done already (a "skip the done ones" query is quadratic).
    /// Rows are in insertion order, which is newest-first because the inventory is written newest-first.
    func imageAssetsNeedingFeatures(afterRowID: Int64 = 0, limit: Int, version: Int) -> (photos: [PhotoSnapshot], lastRowID: Int64) {
        var last = afterRowID
        let photos = (try? rows("""
            SELECT \(Self.assetColumns), a.rowid FROM assets a WHERE a.rowid > ? AND a.deleted=0 AND a.media_type=1
              AND NOT EXISTS (SELECT 1 FROM features f WHERE f.asset_id=a.id AND f.revision=a.revision
                              AND (f.feature_version=? OR f.feature_version=0))
            ORDER BY a.rowid LIMIT ?
            """, bind: { sqlite3_bind_int64($0, 1, afterRowID); sqlite3_bind_int($0, 2, Int32(version)); sqlite3_bind_int($0, 3, Int32(limit)) },
                          map: { s -> PhotoSnapshot in last = max(last, sqlite3_column_int64(s, 11)); return snapshot(from: s) })) ?? []
        return (photos, last)
    }

    func putFeatures(_ items: [(id: String, revision: String, dhash: UInt64)], version: Int) throws {
        try transaction {
            for item in items {
                let h = item.dhash
                try run("""
                    INSERT INTO features(asset_id,revision,dhash,band0,band1,band2,band3,feature_version) VALUES(?,?,?,?,?,?,?,?)
                    ON CONFLICT(asset_id) DO UPDATE SET revision=excluded.revision, dhash=excluded.dhash, band0=excluded.band0,
                      band1=excluded.band1, band2=excluded.band2, band3=excluded.band3, feature_version=excluded.feature_version
                    """) { s in
                    text(s, 1, item.id); text(s, 2, item.revision)
                    sqlite3_bind_int64(s, 3, Int64(bitPattern: h))
                    for band in 0..<4 { sqlite3_bind_int64(s, Int32(4 + band), Int64((h >> UInt64(band * 16)) & 0xffff)) }
                    sqlite3_bind_int(s, 8, Int32(version))
                }
            }
        }
    }

    /// Marks "tried, no local thumbnail" (feature_version 0) so the same asset isn't retried in a loop.
    /// Cleared at the start of each scan so iCloud photos that became local get another chance.
    func markFeaturesUnavailable(_ items: [(id: String, revision: String)]) throws {
        try transaction {
            for item in items {
                try run("""
                    INSERT INTO features(asset_id,revision,dhash,band0,band1,band2,band3,feature_version) VALUES(?,?,0,0,0,0,0,0)
                    ON CONFLICT(asset_id) DO UPDATE SET revision=excluded.revision, feature_version=0
                    """) { s in text(s, 1, item.id); text(s, 2, item.revision) }
            }
        }
    }

    func pendingFeatureCount(version: Int) -> Int {
        (try? rows("""
            SELECT COUNT(*) FROM assets a WHERE a.deleted=0 AND a.media_type=1
              AND NOT EXISTS (SELECT 1 FROM features f WHERE f.asset_id=a.id AND f.revision=a.revision AND (f.feature_version=? OR f.feature_version=0))
            """, bind: { sqlite3_bind_int($0, 1, Int32(version)) }, map: { Int(sqlite3_column_int64($0, 0)) }).first) ?? 0
    }

    /// Current-revision hashes for these assets, for one feature version (v1 and v2 hashes never
    /// mix during the transition scan). Assets without a usable hash are simply absent.
    func dhashes(ids: [String], version: Int = 2) -> [String: UInt64] {
        var out: [String: UInt64] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
            let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let found = (try? rows("""
                SELECT f.asset_id, f.dhash FROM features f JOIN assets a ON a.id=f.asset_id AND a.revision=f.revision
                WHERE f.feature_version=? AND f.asset_id IN (\(marks))
                """, bind: { s in sqlite3_bind_int(s, 1, Int32(version)); for (i, id) in chunk.enumerated() { text(s, Int32(i + 2), id) } },
                                   map: { (String(cString: sqlite3_column_text($0, 0)), UInt64(bitPattern: sqlite3_column_int64($0, 1))) })) ?? []
            for (id, hash) in found { out[id] = hash }
        }
        return out
    }

    /// Burst ids for these assets only (chunked; nil burst assets are absent).
    func burstIDs(among ids: [String]) -> [String: String] {
        var out: [String: String] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
            let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let found = (try? rows("""
                SELECT id, burst_id FROM assets WHERE deleted=0 AND burst_id IS NOT NULL AND id IN (\(marks))
                """, bind: { s in for (i, id) in chunk.enumerated() { text(s, Int32(i + 1), id) } },
                                   map: { (String(cString: sqlite3_column_text($0, 0)), String(cString: sqlite3_column_text($0, 1))) })) ?? []
            for (id, burst) in found { out[id] = burst }
        }
        return out
    }

    /// Pixel dimensions for these assets only (chunked) — for the exact-enqueue narrowing.
    func dimensions(among ids: [String]) -> [String: (width: Int, height: Int)] {
        var out: [String: (width: Int, height: Int)] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
            let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let found = (try? rows("""
                SELECT id, width, height FROM assets WHERE deleted=0 AND id IN (\(marks))
                """, bind: { s in for (i, id) in chunk.enumerated() { text(s, Int32(i + 1), id) } },
                                   map: { (String(cString: sqlite3_column_text($0, 0)),
                                           (Int(sqlite3_column_int($0, 1)), Int(sqlite3_column_int($0, 2)))) })) ?? []
            for (id, dims) in found { out[id] = dims }
        }
        return out
    }

    func clearUnavailableFeatures() throws { try run("DELETE FROM features WHERE feature_version=0") }

    func dhash(id: String, revision: String) -> UInt64? {
        (try? rows("SELECT dhash FROM features WHERE asset_id=? AND revision=?", bind: { text($0, 1, id); text($0, 2, revision) },
                   map: { UInt64(bitPattern: sqlite3_column_int64($0, 0)) }).first) ?? nil
    }

    func featureCount() -> Int { (try? rows("SELECT COUNT(*) FROM features WHERE feature_version>0", map: { Int(sqlite3_column_int64($0, 0)) }).first) ?? 0 }

    /// Candidate near pairs from the four 16-bit LSH bands. A candidate is only a proposal.
    /// Buckets bigger than `maximumBucketSize` are skipped and counted, never silently dropped.
    /// Only the given feature version participates (v1/v2 hashes never mix). The cap is enforced
    /// and the overflow reported (`truncatedPairs`, exact for the band being cut, a lower bound
    /// for the unexamined bands — documented as approximate).
    func nearHashPairs(maxHamming: Int, maximumBucketSize: Int, maximumPairs: Int, version: Int = 2) -> (pairs: [CandidatePair], skippedBuckets: Int, truncatedPairs: Int) {
        var pairs: Set<CandidatePair> = []
        var skipped = 0, truncated = 0
        for band in 0..<4 {
            let column = "band\(band)"
            let sql = """
                SELECT f.\(column), f.asset_id, f.dhash FROM features f JOIN assets a ON a.id=f.asset_id AND a.deleted=0
                WHERE f.feature_version=?
                  AND f.\(column) IN (SELECT \(column) FROM features WHERE feature_version=? GROUP BY \(column) HAVING COUNT(*) BETWEEN 2 AND ?)
                ORDER BY f.\(column)
                """
            let bucketed = (try? rows(sql, bind: { sqlite3_bind_int($0, 1, Int32(version)); sqlite3_bind_int($0, 2, Int32(version)); sqlite3_bind_int($0, 3, Int32(maximumBucketSize)) }, map: { s in
                (sqlite3_column_int64(s, 0), String(cString: sqlite3_column_text(s, 1)), UInt64(bitPattern: sqlite3_column_int64(s, 2)))
            })) ?? []
            var start = 0
            while start < bucketed.count {
                var end = start
                while end < bucketed.count && bucketed[end].0 == bucketed[start].0 { end += 1 }
                var capped = false
                for i in start..<end where !capped { for j in (i + 1)..<end where !capped {
                    guard CandidateIndex.hamming(bucketed[i].2, bucketed[j].2) <= maxHamming else { continue }
                    if pairs.count >= maximumPairs {
                        // Count what this bucket would still have produced (exact for this bucket),
                        // then stop: the remaining bands are a lower bound, reported as approximate.
                        truncated += ((end - i) * (end - i - 1)) / 2
                        capped = true
                        break
                    }
                    pairs.insert(CandidatePair(bucketed[i].1, bucketed[j].1))
                }}
                start = end
                if capped { return (pairs.sorted(), skipped, truncated) }
            }
            let oversized = (try? rows("SELECT COUNT(*) FROM (SELECT \(column) FROM features WHERE feature_version=? GROUP BY \(column) HAVING COUNT(*) > ?)",
                                       bind: { sqlite3_bind_int($0, 1, Int32(version)); sqlite3_bind_int($0, 2, Int32(maximumBucketSize)) }, map: { Int(sqlite3_column_int64($0, 0)) }).first) ?? 0
            skipped += oversized
        }
        return (pairs.sorted(), skipped, truncated)
    }

    /// Every live image with its time, burst and (if available) difference hash, for building review sets.
    /// Only the given feature version participates (v1/v2 hashes never mix).
    func sequenceItems(version: Int = 2) -> [SequenceItem] {
        (try? rows("""
            SELECT a.id, a.created_s, a.burst_id, f.dhash FROM assets a
              LEFT JOIN features f ON f.asset_id=a.id AND f.revision=a.revision AND f.feature_version=?
            WHERE a.deleted=0 AND a.media_type=1
            """, bind: { sqlite3_bind_int($0, 1, Int32(version)) }) { s in
            SequenceItem(id: String(cString: sqlite3_column_text(s, 0)),
                         timeSeconds: sqlite3_column_type(s, 1) == SQLITE_NULL ? nil : sqlite3_column_int64(s, 1),
                         burstID: str(s, 2),
                         hash: sqlite3_column_type(s, 3) == SQLITE_NULL ? nil : UInt64(bitPattern: sqlite3_column_int64(s, 3)))
        }) ?? []
    }

    /// Live image count (cheap progress total for the paged review-set phase).
    func imageAssetCount() -> Int {
        (try? rows("SELECT COUNT(*) FROM assets WHERE deleted=0 AND media_type=1", map: { Int(sqlite3_column_int64($0, 0)) }).first) ?? 0
    }

    /// Burst and time-window pairs for the same-moment candidates (images only). The cap is
    /// enforced in BOTH sections; overflow and oversized burst buckets are reported, never
    /// silently dropped (`pairsDroppedByCap` is exact per section before Set dedup overlaps).
    func momentPairs(maxSecondsApart: Int64, maximumBucketSize: Int, maximumPairs: Int) -> (pairs: [CandidatePair], oversizedBuckets: Int, pairsDroppedByCap: Int) {
        var pairs: Set<CandidatePair> = []
        var oversized = 0, droppedByCap = 0
        var remaining = maximumPairs
        let bursts = (try? rows("SELECT burst_id, id FROM assets WHERE deleted=0 AND media_type=1 AND burst_id IS NOT NULL ORDER BY burst_id, id",
                                map: { (String(cString: sqlite3_column_text($0, 0)), String(cString: sqlite3_column_text($0, 1))) })) ?? []
        var start = 0
        while start < bursts.count {
            var end = start
            while end < bursts.count && bursts[end].0 == bursts[start].0 { end += 1 }
            let n = end - start
            let potential = n * (n - 1) / 2
            if n > maximumBucketSize {
                oversized += 1
            } else if remaining <= 0 {
                droppedByCap += potential
            } else {
                var made = 0
                outer: for i in start..<end { for j in (i + 1)..<end {
                    if made >= remaining { droppedByCap += potential - made; break outer }
                    pairs.insert(CandidatePair(bursts[i].1, bursts[j].1)); made += 1
                }}
                remaining -= made
            }
            start = end
        }
        let timed = (try? rows("SELECT id, created_s FROM assets WHERE deleted=0 AND media_type=1 AND created_s IS NOT NULL ORDER BY created_s, id",
                               map: { (String(cString: sqlite3_column_text($0, 0)), sqlite3_column_int64($0, 1)) })) ?? []
        var left = 0
        for right in timed.indices {
            while timed[left].1 < timed[right].1 - maxSecondsApart { left += 1 }
            let potential = right - left
            if potential > maximumBucketSize { continue }
            if remaining <= 0 { droppedByCap += potential; continue }
            let generated = min(potential, remaining)
            for other in left..<(left + generated) { pairs.insert(CandidatePair(timed[other].0, timed[right].0)) }
            droppedByCap += potential - generated
            remaining -= generated
        }
        return (pairs.sorted(), oversized, droppedByCap)
    }

    // MARK: Receipts (history of what was deleted)

    func addReceipt(id: String, createdAt: Date, json: String) throws {
        try run("INSERT OR REPLACE INTO receipts(id,created_at,payload_json) VALUES(?,?,?)") { s in
            text(s, 1, id); sqlite3_bind_double(s, 2, createdAt.timeIntervalSince1970); text(s, 3, json)
        }
    }

    func receiptJSONs(limit: Int = 200) -> [String] {
        (try? rows("SELECT payload_json FROM receipts ORDER BY created_at DESC LIMIT ?", bind: { sqlite3_bind_int($0, 1, Int32(limit)) },
                   map: { String(cString: sqlite3_column_text($0, 0)) })) ?? []
    }

    // MARK: Protection rules (N05)
    // Unlike the rest of this store these methods THROW. A rule store that silently reads as "empty" would
    // fail open, so every read or write error must reach the caller.

    private static let protectionColumns = "rule_id,kind,target_id,start_local_day,end_local_day,time_zone_id,start_utc,end_utc_exclusive,created_at,updated_at,enabled,rule_version"

    private func protectionRule(from s: OpaquePointer?) -> Result<ProtectionRule, StoreError> {
        func bad(_ why: String) -> Result<ProtectionRule, StoreError> { .failure(.malformedProtectionRule(why)) }
        guard let idText = str(s, 0), let id = UUID(uuidString: idText) else { return bad("rule_id") }
        guard sqlite3_column_int(s, 11) == 1 else { return bad("rule_version") }
        let scope: ProtectionScope
        switch str(s, 1) {
        case "asset":
            guard let target = str(s, 2), !target.isEmpty else { return bad("asset target") }
            scope = .asset(localIdentifier: target)
        case "album":
            guard let target = str(s, 2), !target.isEmpty else { return bad("album target") }
            scope = .album(localIdentifier: target)
        case "date_range":
            guard let startText = str(s, 3), let start = LocalDay(startText),
                  let endText = str(s, 4), let end = LocalDay(endText), end >= start,
                  let zone = str(s, 5), TimeZone(identifier: zone) != nil,
                  sqlite3_column_type(s, 6) != SQLITE_NULL, sqlite3_column_type(s, 7) != SQLITE_NULL else { return bad("date range") }
            let from = Date(timeIntervalSince1970: sqlite3_column_double(s, 6))
            let to = Date(timeIntervalSince1970: sqlite3_column_double(s, 7))
            guard to > from else { return bad("date range interval") }
            scope = .dateRange(start: start, end: end, timeZoneID: zone, startInclusive: from, endExclusive: to)
        default:
            return bad("kind")
        }
        return .success(ProtectionRule(id: id, scope: scope, enabled: sqlite3_column_int(s, 10) == 1,
                                       createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 8)),
                                       updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 9))))
    }

    private func protectionRevision() throws -> Int64 {
        guard let revision = try rows("SELECT revision FROM protection_rule_revision WHERE singleton=1", map: { sqlite3_column_int64($0, 0) }).first else {
            throw StoreError.protectionRevisionMissing
        }
        return revision
    }

    /// All rules plus the current revision. Throws on any unreadable or malformed row.
    func protectionRules() throws -> (revision: Int64, rules: [ProtectionRule]) {
        var revision: Int64 = 0
        var results: [Result<ProtectionRule, StoreError>] = []
        try Self.exec(db, "BEGIN;")
        do {
            revision = try protectionRevision()
            results = try rows("SELECT \(Self.protectionColumns) FROM protection_rules ORDER BY created_at, rule_id", map: { protectionRule(from: $0) })
            try Self.exec(db, "COMMIT;")
        } catch { try? Self.exec(db, "ROLLBACK;"); throw error }
        return (revision, try results.map { try $0.get() })
    }

    /// An existing target or range is left untouched (`ON CONFLICT DO NOTHING`, which, unlike `OR IGNORE`, still raises
    /// CHECK violations so a malformed rule is an error, never silently dropped). The revision moves only if a row was added.
    @discardableResult
    func insertProtectionRules(_ rules: [ProtectionRule]) throws -> Int64 {
        try consumeInjectedProtectionFailure()
        // A rule that could never be evaluated would later make the whole set unreadable: refuse it here.
        for rule in rules {
            switch rule.scope {
            case .asset(let id), .album(let id): if id.isEmpty { throw StoreError.malformedProtectionRule("empty target") }
            case .dateRange: break
            }
        }
        var revision: Int64 = 0
        try transaction {
            var changed = 0
            for rule in rules {
                try run("""
                    INSERT INTO protection_rules(rule_id,kind,target_id,start_local_day,end_local_day,time_zone_id,start_utc,end_utc_exclusive,created_at,updated_at,enabled)
                    VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT DO NOTHING
                    """) { s in
                    text(s, 1, rule.id.uuidString)
                    switch rule.scope {
                    case .asset(let id):
                        text(s, 2, "asset"); text(s, 3, id); sqlite3_bind_null(s, 4); sqlite3_bind_null(s, 5); sqlite3_bind_null(s, 6)
                        sqlite3_bind_null(s, 7); sqlite3_bind_null(s, 8)
                    case .album(let id):
                        text(s, 2, "album"); text(s, 3, id); sqlite3_bind_null(s, 4); sqlite3_bind_null(s, 5); sqlite3_bind_null(s, 6)
                        sqlite3_bind_null(s, 7); sqlite3_bind_null(s, 8)
                    case .dateRange(let start, let end, let zone, let from, let to):
                        text(s, 2, "date_range"); sqlite3_bind_null(s, 3); text(s, 4, start.iso); text(s, 5, end.iso); text(s, 6, zone)
                        sqlite3_bind_double(s, 7, from.timeIntervalSince1970); sqlite3_bind_double(s, 8, to.timeIntervalSince1970)
                    }
                    sqlite3_bind_double(s, 9, rule.createdAt.timeIntervalSince1970)
                    sqlite3_bind_double(s, 10, rule.updatedAt.timeIntervalSince1970)
                    sqlite3_bind_int(s, 11, rule.enabled ? 1 : 0)
                }
                changed += Int(sqlite3_changes(db))
            }
            if changed > 0 { try run("UPDATE protection_rule_revision SET revision = revision + 1 WHERE singleton=1") }
            revision = try protectionRevision()
        }
        return revision
    }

    @discardableResult
    func deleteProtectionRule(id: UUID) throws -> Int64 {
        try consumeInjectedProtectionFailure()
        var revision: Int64 = 0
        try transaction {
            try run("DELETE FROM protection_rules WHERE rule_id=?") { text($0, 1, id.uuidString) }
            if sqlite3_changes(db) > 0 { try run("UPDATE protection_rule_revision SET revision = revision + 1 WHERE singleton=1") }
            revision = try protectionRevision()
        }
        return revision
    }

    @discardableResult
    func deleteAllProtectionRules() throws -> Int64 {
        try consumeInjectedProtectionFailure()
        var revision: Int64 = 0
        try transaction {
            try run("DELETE FROM protection_rules")
            if sqlite3_changes(db) > 0 { try run("UPDATE protection_rule_revision SET revision = revision + 1 WHERE singleton=1") }
            revision = try protectionRevision()
        }
        return revision
    }

    /// Indexed, not-deleted photos captured in `[start, end)`. Informational ("N checked photos in this range").
    func protectedRangeIndexedCount(start: Date, end: Date) -> Int {
        (try? rows("SELECT COUNT(*) FROM assets WHERE deleted=0 AND created_s IS NOT NULL AND created_s>=? AND created_s<?",
                   bind: { sqlite3_bind_int64($0, 1, Int64(start.timeIntervalSince1970.rounded(.up))); sqlite3_bind_int64($0, 2, Int64(end.timeIntervalSince1970.rounded(.up))) },
                   map: { Int(sqlite3_column_int64($0, 0)) }).first) ?? 0
    }

    private var injectedProtectionFailure = false
    private func consumeInjectedProtectionFailure() throws {
        if injectedProtectionFailure { injectedProtectionFailure = false; throw StoreError.sql("injected protection write failure") }
    }

    #if DEBUG
    /// Test seams: the next protection write throws before touching the database; raw SQL for corrupting rows.
    func debugFailNextProtectionWrite() { injectedProtectionFailure = true }
    func debugExecute(_ sql: String) throws { try Self.exec(db, sql) }
    #endif

    // MARK: Maintenance

    func clearFeatures() throws { try run("DELETE FROM features") }

    /// Forget everything derived from the library (keeps schema).
    func reset() throws {
        try transaction {
            for table in ["receipts", "reviews", "group_members", "groups", "digests", "features", "assets", "meta"] { try run("DELETE FROM \(table)") }
        }
    }
}
