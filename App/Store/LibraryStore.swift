import Foundation
import SQLite3
import CleanSlateCore

/// The persistent, rebuildable library index. One SQLite connection owned by this actor.
/// Holds metadata and derived fingerprints only: no photos, thumbnails or faces.
/// (WAL, foreign keys on, versioned migrations, data protection, excluded from backup.)
actor LibraryStore {
    static let schemaVersion = 1

    enum StoreError: Error { case open(String), sql(String) }

    // Only touched by this actor (and its deinit, which has exclusive access).
    nonisolated(unsafe) private var db: OpaquePointer?
    let path: String?

    /// `path == nil` opens an in-memory database (tests).
    init(path: String?) throws {
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
        try Self.migrate(handle)
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
        """
    ]

    private static func migrate(_ db: OpaquePointer?) throws {
        var current = 0
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW {
            current = Int(sqlite3_column_int(statement, 0))
        }
        sqlite3_finalize(statement)
        guard current < migrations.count else { return }
        for version in current..<migrations.count {
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
                    text(s, 10, photo.record.flags.map(\.rawValue).sorted().joined(separator: ","))
                    text(s, 11, photo.originalFilename)
                    sqlite3_bind_double(s, 12, now)
                }
            }
        }
    }

    func markDeleted(_ ids: [String]) throws {
        try transaction { for id in ids { try run("UPDATE assets SET deleted=1 WHERE id=?") { text($0, 1, id) } } }
    }

    /// After a full inventory: anything not seen since the run started is gone from the library.
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

    /// Current-revision hashes for these assets (assets without a usable hash are simply absent).
    func dhashes(ids: [String]) -> [String: UInt64] {
        var out: [String: UInt64] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
            let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let found = (try? rows("""
                SELECT f.asset_id, f.dhash FROM features f JOIN assets a ON a.id=f.asset_id AND a.revision=f.revision
                WHERE f.feature_version>0 AND f.asset_id IN (\(marks))
                """, bind: { s in for (i, id) in chunk.enumerated() { text(s, Int32(i + 1), id) } },
                                   map: { (String(cString: sqlite3_column_text($0, 0)), UInt64(bitPattern: sqlite3_column_int64($0, 1))) })) ?? []
            for (id, hash) in found { out[id] = hash }
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
    func nearHashPairs(maxHamming: Int, maximumBucketSize: Int, maximumPairs: Int) -> (pairs: [CandidatePair], skippedBuckets: Int) {
        var pairs: Set<CandidatePair> = []
        var skipped = 0
        for band in 0..<4 {
            let column = "band\(band)"
            let sql = """
                SELECT f.\(column), f.asset_id, f.dhash FROM features f JOIN assets a ON a.id=f.asset_id AND a.deleted=0
                WHERE f.feature_version>0
                  AND f.\(column) IN (SELECT \(column) FROM features WHERE feature_version>0 GROUP BY \(column) HAVING COUNT(*) BETWEEN 2 AND ?)
                ORDER BY f.\(column)
                """
            let bucketed = (try? rows(sql, bind: { sqlite3_bind_int($0, 1, Int32(maximumBucketSize)) }, map: { s in
                (sqlite3_column_int64(s, 0), String(cString: sqlite3_column_text(s, 1)), UInt64(bitPattern: sqlite3_column_int64(s, 2)))
            })) ?? []
            var start = 0
            while start < bucketed.count {
                var end = start
                while end < bucketed.count && bucketed[end].0 == bucketed[start].0 { end += 1 }
                for i in start..<end { for j in (i + 1)..<end where CandidateIndex.hamming(bucketed[i].2, bucketed[j].2) <= maxHamming {
                    pairs.insert(CandidatePair(bucketed[i].1, bucketed[j].1))
                    if pairs.count >= maximumPairs { return (pairs.sorted(), skipped) }
                }}
                start = end
            }
            let oversized = (try? rows("SELECT COUNT(*) FROM (SELECT \(column) FROM features WHERE feature_version>0 GROUP BY \(column) HAVING COUNT(*) > ?)",
                                       bind: { sqlite3_bind_int($0, 1, Int32(maximumBucketSize)) }, map: { Int(sqlite3_column_int64($0, 0)) }).first) ?? 0
            skipped += oversized
        }
        return (pairs.sorted(), skipped)
    }

    /// Every live image with its time, burst and (if available) difference hash, for building review sets.
    func sequenceItems() -> [SequenceItem] {
        (try? rows("""
            SELECT a.id, a.created_s, a.burst_id, f.dhash FROM assets a
              LEFT JOIN features f ON f.asset_id=a.id AND f.revision=a.revision AND f.feature_version>0
            WHERE a.deleted=0 AND a.media_type=1
            """) { s in
            SequenceItem(id: String(cString: sqlite3_column_text(s, 0)),
                         timeSeconds: sqlite3_column_type(s, 1) == SQLITE_NULL ? nil : sqlite3_column_int64(s, 1),
                         burstID: str(s, 2),
                         hash: sqlite3_column_type(s, 3) == SQLITE_NULL ? nil : UInt64(bitPattern: sqlite3_column_int64(s, 3)))
        }) ?? []
    }

    /// Burst and time-window pairs for the same-moment candidates (images only).
    func momentPairs(maxSecondsApart: Int64, maximumBucketSize: Int, maximumPairs: Int) -> [CandidatePair] {
        var pairs: Set<CandidatePair> = []
        let bursts = (try? rows("SELECT burst_id, id FROM assets WHERE deleted=0 AND media_type=1 AND burst_id IS NOT NULL ORDER BY burst_id, id",
                                map: { (String(cString: sqlite3_column_text($0, 0)), String(cString: sqlite3_column_text($0, 1))) })) ?? []
        var start = 0
        while start < bursts.count {
            var end = start
            while end < bursts.count && bursts[end].0 == bursts[start].0 { end += 1 }
            if end - start <= maximumBucketSize {
                for i in start..<end { for j in (i + 1)..<end { pairs.insert(CandidatePair(bursts[i].1, bursts[j].1)) } }
            }
            start = end
        }
        let timed = (try? rows("SELECT id, created_s FROM assets WHERE deleted=0 AND media_type=1 AND created_s IS NOT NULL ORDER BY created_s, id",
                               map: { (String(cString: sqlite3_column_text($0, 0)), sqlite3_column_int64($0, 1)) })) ?? []
        var left = 0
        for right in timed.indices {
            while timed[left].1 < timed[right].1 - maxSecondsApart { left += 1 }
            if right - left > maximumBucketSize { continue }
            for other in left..<right { pairs.insert(CandidatePair(timed[other].0, timed[right].0)) }
            if pairs.count >= maximumPairs { break }
        }
        return pairs.sorted()
    }

    // MARK: Maintenance

    func clearFeatures() throws { try run("DELETE FROM features") }

    /// Forget everything derived from the library (keeps schema).
    func reset() throws {
        try transaction {
            for table in ["receipts", "reviews", "group_members", "groups", "digests", "features", "assets", "meta"] { try run("DELETE FROM \(table)") }
        }
    }
}
