# Architecture (as built through Step 5)

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
`DeletionTray` → `PhotoDeletionCoordinator.commit` (duplicates) or `commitStandalone` (screenshots, large videos)
→ fresh snapshots → `SafetyPolicy.validateCommit` / `validateStandalone` → byte rehash (exact) → full policy again
→ `PhotoLibraryClient.delete(ids:expectedRevisions:)` (re-reads the exact objects, one `deleteAssets` call)
→ Apple's system prompt. `scripts/check_policy_separation.sh` (in `make lint`) enforces: one `deleteAssets`,
each policy called from exactly one function.

## Scan pipeline (`ScanEngine.run`)
1. **Inventory sync.** Resume an interrupted full inventory (`inventory.offset`) or catch up from the saved
   persistent-change token; an expired/unsupported token falls back to a full inventory; anything not seen in a full
   run is marked deleted. Pages of 1,000 → one SQLite transaction each.
2. **Fingerprints.** Difference hash per image, in batches of 200 committed to `features` (so a kill loses at most one
   batch). Concurrency follows the governor (≤ 4). Assets with no local thumbnail are marked "unavailable" and retried
   next scan. Fingerprints are keyed by asset revision, so an edit invalidates them.
3. **Candidates** (queries, no whole-library arrays): exact-copy buckets from metadata; near pairs from four 16-bit LSH
   bands + burst/time windows; ranked bursts-first then by Hamming distance.
4. **Exact verification.** Smaller buckets first, capped at 4,000 fully hashed assets per scan (remainder reported).
   Every resource of every asset is hashed; unreadable == not a match. Groups appear as they're found.
5. **Keeper-less lists.** Screenshots/videos without protection flags; video sizes from the local file; album members
   from one set per scan.
6. **Similar shots.** Vision feature print per candidate pair (device only), manual review only, capped at 30,000 pairs
   per pass (reported).

## Resource governance
`ResourceGovernor.checkpoint()` between batches: `.critical` thermal → stop (progress saved); `.serious` → pause up to
10 minutes with a visible reason; `.fair`/low memory/Low Power → narrower concurrency.

## Persistence
`library-index.sqlite` (Application Support, WAL, complete-until-first-unlock, excluded from backup): rebuildable
cache of metadata + fingerprints. `tray.json`: approvals (excluded from backup). Neither holds image data.
