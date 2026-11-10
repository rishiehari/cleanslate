# F08: Check more, with an honest coverage ledger

## Goal and story
*After my first 100, I can check more at my own pace (500, 1,000, 5,000, everything) without redoing the work already
done. I always know how much of my library has been checked and what couldn't be.*

## Trust / privacy / safety
- Honest coverage: "Checked 600 of 8,310. 23 couldn't be checked (only in iCloud)". Never "Your library is clean".
- Ladder steps are **cumulative recent scopes** (Recent 600 includes the first 100), so copies and bursts that cross
  the boundary are found. Already-done work is reused from the cache, keyed by revision, so an edited photo is
  re-checked.
- Cached Vision prints and quality signals are advisory only (they rank and propose), the same as today. No change to
  what can be pre-marked (exact only) or deleted.

## Device tier
- Reuse: thumbnails/fingerprints (already cached by revision), **feature prints and quality now persisted** (below), and
  pairs already compared are skipped. Going from 100 to 600 therefore reads ~500 new thumbnails plus Vision work for new
  pairs only.
- Feature print blob ≈ 2–8 KB (UNVERIFIED; measure). It is stored only for assets in candidate pairs. DB growth is
  logged in diagnostics; budget ≤ 40 MB at 10k candidates.
- One step at a time; the "everything" step keeps F03's caps and reports what is left.

## Data model: migration v4 (`user_version` 3 → 4)
```sql
ALTER TABLE features ADD COLUMN featureprint BLOB;      -- binary plist of the Codable observation (Appendix C)
ALTER TABLE features ADD COLUMN quality_json TEXT;      -- QualitySignals JSON
CREATE TABLE checked(asset_id TEXT PRIMARY KEY, revision TEXT NOT NULL, checked_at REAL NOT NULL, complete INTEGER NOT NULL);
CREATE TABLE compared_pairs(a TEXT NOT NULL, b TEXT NOT NULL, rev_a TEXT NOT NULL, rev_b TEXT NOT NULL, distance REAL, PRIMARY KEY(a, b));
```
- `checked.complete = 1` only when the scope **finished with no skipped stage**; otherwise 0 ("partly checked").
- `compared_pairs` rows are valid only while both revisions match. Stale rows are ignored and deleted lazily.
- `LibraryStore.reset()` clears all four with the rest of the index.

## Files
| Action | Path |
|---|---|
| modify | `App/Models/ScanScope.swift`: `static let ladder: [Int] = [100, 500, 1_000, 5_000]`; `func next(after: ScanScope, libraryCount: Int) -> ScanScope?` (then `.everything`) |
| modify | `App/Store/LibraryStore.swift`: migration v4; `markChecked(scopeIDs:complete:)` (via `scan_scope`), `coverage() -> Coverage`, print/quality get/put, compared-pair get/put |
| modify | `App/Services/ScanEngine.swift`: read/write cached prints and quality; skip compared pairs (reuse the stored distance to rebuild the group when < 0.32); call `markChecked` at the end |
| modify | `App/Services/VisualAnalyzing.swift`: `VisualPrint` gains `func encoded() throws -> Data` and `static func decode(_:) throws -> VisualPrint` (real version: `PropertyListEncoder` binary of `FeaturePrintObservation`; fake: JSON of the spec) |
| create | `App/Views/CheckMoreCard.swift`, `App/Views/CoverageView.swift` |
| create | `App/Views/LimitedLibraryButton.swift`: `UIViewControllerRepresentable` host that calls `PHPhotoLibrary.shared().presentLimitedLibraryPicker(from:completionHandler:)` (PhotosUI, iOS 15+, verified) |
| modify | `App/Views/DashboardView.swift`: `CheckMoreCard` after a finished scope |
| create | `iOSTests/CoverageTests.swift`, `UITests/CheckMoreUITests.swift` |

## Types
```swift
struct Coverage: Equatable, Sendable { let checked: Int; let partlyChecked: Int; let couldntCheck: Int; let libraryCount: Int }
// couldntCheck = in-scope assets whose features are 'unavailable' (feature_version 0) or whose digests timed out
```

## UI spec
**CheckMoreCard** (`checkmore.card`): "You've checked your 100 most recent photos." Primary **"Check 400 more"**
(`checkmore.next`) with the subtitle "Your 500 most recent · uses more battery". Secondary **"Choose…"** opens F04's picker.
When everything is checked: "You've checked all 8,310 photos and videos" with "Check again" (incremental).
**CoverageView** (`coverage.screen`), from the card's info button and the menu: a ring or `Gauge` "600 of 8,310
checked" (accessibility value "7 percent checked"), rows Checked / Partly checked ("a step was skipped") / Couldn't
check ("only in iCloud, or took too long") / Not yet checked, plus a short "Why some photos can't be checked" explainer
(iCloud originals, link to the existing iCloud sheet).
**Limited access**: the card reads "You've shared 40 photos with CleanSlate" with **"Choose more photos"**
(`checkmore.limited`), which presents the system limited-library picker. After it changes, the PhotoKit change observer
triggers the normal incremental path.

## Sub-tasks
1. Migration v4 + store APIs + migration test.
2. Persist and reuse prints and quality (encode/decode through the seam) + tests (the second identical scan makes 0 Vision calls).
3. `compared_pairs` reuse + revision invalidation tests.
4. `checked` marking + `coverage()` + tests (skipped stage → partly checked).
5. Ladder `next(after:)` + `CheckMoreCard` + `CoverageView`.
6. Limited-library button + UI tests + accessibility audit.

## Acceptance criteria
- Fake 2,000 photos: Recent 100 → Check more (500). The second scan's `fingerprintThumbnailCalls` is ≤ 400 + (assets
  whose revision changed), and its Vision calls cover new pairs only. A burst straddling positions 95–105 is found as
  one set in the 500 scan.
- An edit to a checked photo (fake `update(revision:)`) makes it "not yet checked" again, and it is re-fingerprinted.
- Coverage numbers equal SQL ground truth in every test. "Couldn't check" counts timed-out and unavailable items.
- Memory: `MemoryBudgetTests` adds the ladder 100 → 500 → 1,000 → 5,000 on SE-test, staying within the tier budget, flat.

## Test plan / validator checklist
Corner: the library shrinks below the next step (the step becomes "everything"); a deleted photo leaves the ledger;
token expired between steps (full inventory, cache by revision keeps the work); corrupted blob (decode fails → recompute,
never crash); `reset()` clears coverage. Negatives: a cached distance never makes a similar pair pre-marked; a stale
`compared_pairs` row (revision changed) is never used.

## Privacy review
New on-device derived data (prints, quality, pairs). No image data. The F06 "Data on this iPhone" row for the scan
index now covers them (size shown). Still excluded from backup.

## Rollback
The card can be hidden. Disabling the cache reads (flag `cache.v4Reads`) falls back to recompute. The migration is additive.

## Dependencies
F04, F05 (progress for larger steps), F03 (caps). Precedes F09 (coverage numbers shown next to kept-safe).

## Definition of done
Tests and the budget test green, screenshots, validator + gatekeeper approved. 🧑 Device: the ladder up to 1,000 on a
tier-L/M device, with time per step and footprint logged.
