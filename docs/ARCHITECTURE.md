# Architecture (updated through F03, 2026-11-11)

```
SwiftUI views ──▶ CleaningViewModel (main actor, ScanReporting) ──▶ ScanEngine (main actor)
                      │  tray: DeletionTray (JSON, approvals)           │
                      │  coordinator: PhotoDeletionCoordinator          ├─▶ LibraryStore (actor, SQLite WAL)
                      ▼                                                 ├─▶ ResourceGovernor (heat / memory / power)
                PhotoLibraryClient (protocol)                           ├─▶ NetworkPolicy + DigestFetcher (opt-in iCloud)
                  ├─ PhotoKitLibraryClient (production)                 └─▶ Core (pure Swift, runs on Linux)
                  └─ FakePhotoLibrary (DEBUG: tests, UI tests, previews)      ├─ SafetyPolicy (+ standalone), ReviewDraft
                                                                              ├─ ExactCandidates, CandidateIndex, KeeperRanker
                                                                              └─ ResourceSignatures, SafetyStatistics
```

## The only way a photo gets deleted
`DeletionTray.deleteAll` → `PhotoDeletionCoordinator.commitBatch`
→ fresh snapshots → batch evaluator (`SafetyPolicy.validateBatch` / `validateStandalone`) → byte rehash (exact) → full evaluation again
→ `PhotoLibraryClient.delete(ids:expectedRevisions:)` (re-reads the exact objects, one `deleteAssets` call)
→ Apple's system prompt. `scripts/check_policy_separation.sh` (in `make lint`) enforces: one `deleteAssets`,
policy calls only from their allowed commit/evaluator/advisory recheck functions. Individually tested `commit`
and `commitStandalone` paths retain their respective guards; `TrayChecker` is advisory and does not delete.

## Scan pipeline (`ScanEngine.run`)
1. **Inventory sync.** Resume an interrupted full inventory (`inventory.offset`) or catch up from the saved
   persistent-change token; an expired/unsupported token falls back to a full inventory; anything not seen in a full
   run is marked deleted. Pages of 1,000 → one SQLite transaction each.
2. **Fingerprints.** 128-pixel difference hash (feature version 2), paged in batches of 200 committed to `features`.
   The engine enforces one asset in flight on every tier. Assets with no local thumbnail are marked "unavailable"
   and retried next scan. Fingerprints are keyed by asset revision, so an edit invalidates them.
3. **Candidates** (queries, no whole-library arrays): exact-copy buckets from metadata; near pairs from four 16-bit LSH
   bands + burst/time windows; ranked bursts-first then by Hamming distance.
4. **Exact verification.** Smaller buckets first, capped at 4,000 fully hashed assets per scan (remainder reported).
   Every resource of every selected candidate is hashed; unreadable == not a match. Groups appear as they're found.
5. **Keeper-less lists.** Screenshots/videos without protection flags; video sizes from the local file. Album checks
   are targeted to relevant IDs and yield periodically.
6. **Similar shots.** Vision feature print per candidate pair (device only), manual review only, capped at 30,000 pairs
   per pass and three times the scope count, whichever is smaller (reported). Vision prints and quality signals use
   bounded caches; candidate generation has per-tier caps. Temporal review sets do not prove pairwise visual similarity.

## Resource governance
`ResourceGovernor.checkpoint()` between batches: `.critical` thermal → stop (progress saved); `.serious` → pause up to
10 minutes with a visible reason; memory pressure pauses and drops caches. Concurrency remains capped at one.
Thumbnail, video-size and Vision requests have 10-second deadlines; digest streaming has a 20-second inactivity
deadline. Diagnostics record stage counts, timeouts, heartbeat, and main-thread watchdog events locally. UI scan
publication is coalesced rather than emitted for every asset.

**Remaining device risk:** `PhotoKitLibraryClient` is still main-actor isolated, and inventory snapshots enumerate
resource metadata synchronously. Fake-library watchdog tests do not establish that the owner's real PhotoKit
metadata-fetch hang is resolved. F03's Instruments/device gate remains PENDING. F04 scoped inventory is not implemented.

## Persistence
`library-index.sqlite` (Application Support, WAL, complete-until-first-unlock, excluded from backup): rebuildable
cache of metadata + fingerprints. `tray.json`: approvals (excluded from backup). Neither holds image data.
