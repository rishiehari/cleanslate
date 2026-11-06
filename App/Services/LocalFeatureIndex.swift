import Foundation
import SQLite3

/// On-device metadata cache only. No thumbnails, faces, or original photos are stored.
final class LocalFeatureIndex {
    private let db: OpaquePointer?
    init() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var opened: OpaquePointer?
        let result = sqlite3_open(url.appendingPathComponent("cleanslate.sqlite").path, &opened)
        guard result == SQLITE_OK else {
            if opened != nil { sqlite3_close(opened) }
            db = nil
            return
        }
        db = opened
        // This cache contains only derived fingerprints and PhotoKit IDs, but should
        // still receive iOS Data Protection on disk.
        try? FileManager.default.setAttributes([
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ], ofItemAtPath: url.appendingPathComponent("cleanslate.sqlite").path)
        let sql = """
        CREATE TABLE IF NOT EXISTS visual_features (
            asset_id TEXT PRIMARY KEY, revision TEXT NOT NULL,
            dhash TEXT NOT NULL, analyzed_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_revision ON visual_features(revision);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }
    deinit { if db != nil { sqlite3_close(db) } }

    func hash(for id: String, revision: String) -> UInt64? {
        guard let db else { return nil }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT dhash FROM visual_features WHERE asset_id=? AND revision=?", -1, &statement, nil) == SQLITE_OK else { return nil }
        bind(id, at: 1, in: statement)
        bind(revision, at: 2, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { return nil }
        return UInt64(String(cString: value), radix: 16)
    }

    func put(_ hash: UInt64, for id: String, revision: String) {
        guard let db else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "INSERT OR REPLACE INTO visual_features(asset_id,revision,dhash,analyzed_at) VALUES(?,?,?,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        bind(id, at: 1, in: statement)
        bind(revision, at: 2, in: statement)
        bind(String(format:"%016llx", hash), at: 3, in: statement)
        sqlite3_bind_double(statement, 4, Date().timeIntervalSince1970)
        sqlite3_step(statement)
    }

    func clear() {
        if let db { sqlite3_exec(db, "DELETE FROM visual_features", nil, nil, nil) }
    }

    private func bind(_ string: String, at index: Int32, in statement: OpaquePointer?) {
        // SQLITE_TRANSIENT ensures the C statement owns its own copy.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = string.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
    }
}
