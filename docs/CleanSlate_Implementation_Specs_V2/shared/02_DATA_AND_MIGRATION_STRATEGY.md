# Data ownership, migration allocation, caching, and crash consistency

## 1. The repository's actual database

The observed `App/Store/LibraryStore.swift` owns one SQLite connection behind an actor. Its source declares `schemaVersion = 1` and a `migrations: [String]` list. In the same inspected source, v1 creates `meta`, `assets`, `features`, `digests`, `groups`, `group_members`, `reviews`, and `receipts`. There may be newer migrations by the time a feature starts. **Never copy a feature's `v2`/`v3` label blindly.** The feature SQL snippets below are templates to append to the latest migration, with dependencies implemented before their use. Assign and document exact `PRAGMA user_version` in the implementation PR.

The database is a **rebuildable index**, not the authoritative Photos library. `LibraryStore.reset()` must not silently destroy user decisions or receipts; give nonrebuildable preferences and approved tray state explicit ownership and reset semantics.

## 2. Proposed shared relational model

```sql
-- Namespace for independent feature migration batches, not a literal single next-version migration.
CREATE TABLE IF NOT EXISTS feature_progress (
    feature_id TEXT PRIMARY KEY,
    schema_version INTEGER NOT NULL,
    algorithm_version INTEGER NOT NULL,
    cursor_json TEXT,
    status TEXT NOT NULL CHECK(status IN ('not_started','running','paused','completed','stale','failed')),
    scanned_count INTEGER NOT NULL DEFAULT 0,
    unresolved_count INTEGER NOT NULL DEFAULT 0,
    updated_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS local_impact_event (
    event_id TEXT PRIMARY KEY,
    feature_id TEXT NOT NULL,
    event_kind TEXT NOT NULL,
    created_at_bucket INTEGER NOT NULL,
    duration_ms_bucket INTEGER,
    count_bucket INTEGER,
    bytes_bucket INTEGER,
    schema_version INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS impact_by_feature ON local_impact_event(feature_id, created_at_bucket);
```

An event may contain **numeric bins**, never raw asset IDs, OCR tokens, filenames, location, person identity, face embeddings, exact photo timestamps or media. Keep only a bounded 90-day local rolling window unless user chooses 'Retain history on this device'; this is a proposed product policy, not a preexisting repo guarantee. All counters recompute from local records where feasible to prevent drift.

## 3. Asset-scoped cache key

For any new feature cache, use the composite identity `(asset_id, asset_revision, algorithm_version, model_version, relevant_parameters_hash)`. On every read verify the current asset revision, known authorization scope, safety protection version and model hash. Do not reuse `dhash` as a unique identifier. An asset can have a Live component, RAW+JPEG, adjusted edit, or multiple resources; use `PHAssetResource` type when reading only accessible metadata. Cache *only* derived values required for current features. Eviction must be deterministic and tested.

## 4. Migration pattern

Append an ordered migration to the existing actor migration list. Use `BEGIN IMMEDIATE`/`COMMIT` with rollback on error; do not alter migration history. After adding each table, create matching indices and a transaction integrity test. If backfill is needed, put it in a resumable job rather than a long migration blocking launch; store backfill progress and per-asset version. A migration that needs to transform user-protection rules must fail closed and leave protection enabled on unexpected input.

Suggested test sequence:

1. Create a temporary DB at the preceding real user_version.
2. Populate assets, features, digests, groups, reviews, receipts and tray-serialized data representing protected/edit/Live/media cases.
3. Open with the new `LibraryStore`, assert version increment and all existing values preserved.
4. Simulate a process crash between backfill pages, reopen and continue without duplication.
5. Simulate malformed feature payload, expect no crash and stale feature disabled.
6. Simulate downgrade to older app binary: older binary must not overwrite/interpret unknown columns. Document policy (block old binary or store only additive data).
7. Run `PRAGMA integrity_check` after migration; check that index and child-table counts match.

## 5. Crash-safe work ledger

Each long-running job gets an immutable `job_id` (UUID) with phase/status. Write per-step checkpoints before expensive I/O. A resumed job revalidates PhotoKit permissions and live revisions and never assumes an old result is still safe. Staging temporary exports must be in application-controlled protected storage with `NSFileProtectionCompleteUntilFirstUserAuthentication`, excluded from backup; cleanup abandoned files after checking against the job ledger. A media derivative `createdAssetID` becomes known only after Photos reconciliation; never treat an attempted Photos creation call as proof.

Atomic data decisions that must be in one SQL transaction: user protection rule + its version update; swipe approval + prepared draft state; compression job stage and output asset identifier; album operation state + idempotency key; model opt-in + version and reset state. PhotoKit changes cannot be transacted with SQLite. Therefore use a **saga**: `pending → Photos operation → verify PhotoKit state → database reconciliation`, recording uncertain operations explicitly.

## 6. Privacy controls and per-feature reset

The Settings screen must expose a **Delete CleanSlate Local Data** action. Its confirmation discloses: generated fingerprints, OCR-derived fingerprints, on-device activity counters, model preferences, temporary compression outputs, category selections, scan cursors, protected lists, and optional diagnostics. The currently approved deletion tray is user safety state: clearing it requires a dedicated explicit description and must not cause deletion. Do not clear Apple Photos library assets through this function. Revoking Photos access does not itself delete private local data; offer a separate reset.

## 7. Query discipline at scale

For 250k indexed assets: use `LIMIT` + deterministic keyset cursor `(created_s,id)` or rowid with an explicit stable snapshot; avoid a `SELECT *` materialized Swift array. For candidate retrieval use approximate/bucketed heuristics and bounded collections, never an all-pairs video/screenshot/Moment comparison. Proposed query budgets should be recorded in instruments (p50/p95 and peak RSS), not invented. The initial implementation must not promise exhaustive search when query caps/truncation apply; show a coverage ledger including exact counts examined, feature families skipped, permissions limitations and iCloud unavailable items.
