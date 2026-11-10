# F07: Activity log and Impact (on-device only)

## Goal and story
*I can see what CleanSlate has done for me: space freed, photos deleted, checks run, what it kept safe, and how often
I changed my mind. It's all private, on my phone. I can delete it or export it myself.*

## Trust / privacy / safety
- Stored in the local index (new table), never transmitted. Export only via a user-tapped `ShareLink`.
- **No identifiers**: events hold kinds, counts and byte totals only. No asset ids, filenames, dates of photos, album
  names or places. The same leak test as Label mode and F02.
- Numbers never lie (U10): "space freed" = verified file sizes of photos Apple confirmed deleted, labeled with the
  Recently Deleted caveat. Free-space before/after is shown as a measurement. "Time saved" is an **estimate** with its
  formula shown. Verified and estimated numbers are never added together.
- Read-only with respect to photos. Logging failures never block approve or delete.

## Device tier
Append is one small INSERT on the store actor, off the main thread. The Impact screen reads aggregates with SQL
(`SUM`/`COUNT`), never all rows; the activity list pages 50 at a time. Retention: 10,000 events or 24 months, trimmed
at launch. Footprint impact < 1 MB.

## Data model: migration v3 (`user_version` 2 → 3)
```sql
CREATE TABLE activity(
  seq INTEGER PRIMARY KEY AUTOINCREMENT, at REAL NOT NULL, kind TEXT NOT NULL, payload TEXT NOT NULL);
CREATE INDEX activity_at ON activity(at);
```
`LibraryStore.reset()` ("Clear saved scan data") **does not** delete `activity`. Activity has its own delete. Update
the alert copy accordingly.

## Files
| Action | Path |
|---|---|
| create | `App/Activity/ActivityEvent.swift` |
| create | `App/Activity/ActivityLog.swift`: `actor ActivityLog` over `LibraryStore` |
| create | `App/Activity/ImpactSummary.swift`: pure aggregation (unit-tested) |
| modify | `App/Store/LibraryStore.swift`: migration v3, `appendActivity`, `activityPage`, `activityAggregates`, `deleteActivity`, `trimActivity` |
| modify | `App/Services/CleaningViewModel.swift`: record scan start/finish (+ kept-safe counts), tray delete outcome |
| modify | `App/Store/DeletionTray.swift`: `var onEvent: (@MainActor (ActivityEvent) -> Void)?`, fired on approve / approveAll / skip / undo / remove / clear / prompt declined / batch blocked |
| create | `App/Views/ImpactView.swift`, `App/Views/ActivityListView.swift`, `App/Views/ImpactCard.swift` (Home) |
| modify | `App/Views/DashboardView.swift`: `ImpactCard` below the categories when there is ≥ 1 event; menu "Activity" |
| modify | `App/Services/LocalDataInventory.swift` (F06): include `.activityLog` |
| create | `iOSTests/ActivityLogTests.swift`, `iOSTests/ImpactSummaryTests.swift`, `UITests/ImpactUITests.swift` |

## Types
```swift
enum ActivityEvent: Codable, Sendable, Equatable {
    case checkStarted(scope: String)                                   // ScanScope.diagnosticsName
    case checkFinished(scope: String, outcome: String, photosChecked: Int, copySets: Int, similarSets: Int, keptSafe: KeptSafeCounts, seconds: Int)
    case approved(kind: String, photos: Int, verifiedBytes: Int64)     // kind: copies|similar|screenshots|videos|large
    case skipped(kind: String)
    case undone(action: String)                                        // approve|skip
    case removedFromTray(photos: Int)
    case deleted(requested: Int, verifiedRemoved: Int, uncertain: Int, verifiedBytes: Int64, freeBefore: Int64?, freeAfter: Int64?)
    case applePromptDeclined(photos: Int)
    case blockedForSafety(groups: Int)                                 // "changed since approval" set-asides
    case suggestionCorrected
}
struct KeptSafeCounts: Codable, Sendable, Equatable { var favorites = 0, albums = 0, edited = 0, shared = 0, livePhotos = 0, raw = 0, other = 0 }

actor ActivityLog {
    init(store: LibraryStore, now: @Sendable () -> Date = Date.init)
    func record(_ event: ActivityEvent)
    func page(before seq: Int64?, limit: Int) -> [(seq: Int64, at: Date, event: ActivityEvent)]
    func summary() -> ImpactSummary
    func exportFile() throws -> URL          // JSON array, temp dir
    func deleteAll() throws
}
struct ImpactSummary: Equatable, Sendable {
    var verifiedBytesFreed: Int64; var photosDeleted: Int; var checksRun: Int; var lastCheck: Date?
    var lastKeptSafe: KeptSafeCounts; var approvals: Int; var skips: Int; var undos: Int; var promptsDeclined: Int
    var blockedForSafety: Int
    var estimatedMinutesSaved: Int            // ESTIMATE: photosReviewed × 4 s / 60, rounded down; label as estimate
    var monthlyBytesFreed: [(month: DateComponents, bytes: Int64)]   // last 12 months, SQL GROUP BY
}
```
Kept safe = members of groups found in that check that carry a preservation flag (taken from the found groups'
snapshots at scan end; no extra PhotoKit calls). F09 makes these tappable.

## UI spec
**ImpactCard** (Home, `impact.card`): "Freed so far: 1.2 GB · 214 photos". Caption: "Verified file sizes. Space
returns after Recently Deleted is emptied." Tap → ImpactView.

**ImpactView** (`impact.screen`), `ScrollView`, no glass on content:
- Hero tile: verified bytes freed (`impact.freed`), `.numericText()`.
- Tiles grid (2 columns; 1 column at AX sizes): Photos deleted (`impact.deleted`), Checks run (`impact.checks`),
  Kept safe in your last check (`impact.keptsafe`, with a breakdown line "38 favorites · 12 in albums · 5 edited"),
  You changed your mind (`impact.undos`: undos + prompts declined; caption "That's the point: you're in control"),
  Time saved (`impact.time`: "≈ 25 min (estimate)" with an info button showing the formula).
- Chart: last 12 months of verified bytes freed (Swift Charts `BarMark`). Each bar has an accessibility label
  ("March, 340 MB"). Hidden when fewer than 2 months have data.
- Footer link: "See activity" → ActivityListView.

**ActivityListView** (`activity.screen`): grouped by day, plain words ("Checked your 100 most recent photos: 3 sets of
copies", "Approved 2 copies (4.1 MB)", "You cancelled Apple's prompt; nothing was deleted"), paged 50 at a time. Toolbar
menu: **Share activity file** (`activity.share`, ShareLink, with the preview line "Counts and sizes only. No photos,
names or places."), **Delete activity** (`activity.delete`, alert). Empty: `ContentStateView` "Nothing yet: your
checks and choices will show up here."

## Sub-tasks
1. Migration v3 + store methods + `reset()` exclusion + migration test (v2 → v3 keeps data).
2. `ActivityEvent`, `ActivityLog`, `ImpactSummary` aggregation + unit tests (golden numbers).
3. Hooks: tray `onEvent`, view-model scan and delete events, prompt-declined path, blocked-for-safety path.
4. `ImpactCard` + `ImpactView` + chart.
5. `ActivityListView` + export + delete + data-inventory entry.
6. UI tests + accessibility audits + leak test.

## Acceptance criteria
- E2E (F01 Recent 100): scan → approve 5 → undo 1 → approve again → delete (fake success). Then the summary gives
  photosDeleted 5, verifiedBytesFreed = the sum of the planted bytes, undos 1, checksRun 1, keptSafe.favorites ≥ 1.
- Fake `deleteOutcome = .userCancelled` gives `promptsDeclined == 1` and no bytes freed.
- Leak test: the export contains none of the fake ids, filenames or capture dates; keys are from the allow-list.
- "Clear saved scan data" leaves the activity count unchanged. "Delete activity" empties it. Forget everything (F06) empties it.
- `performAccessibilityAudit()` passes on ImpactView and ActivityListView, also at AX5.

## Test plan / validator checklist
Unit: aggregation with 0 events; with only declined prompts; months spanning a year boundary; trimming at 10,001 events
and at 24 months + 1 day. Negative: logging throws (closed store), so approve and delete still succeed; verified and
estimated numbers are never summed (assert on the view model's formatted strings). Corner: limited access, where deleted
counts are "uncertain" and only the verified number is shown; clock changes.

## Privacy review
Local only, allow-listed, user-exported. 🧑 The owner confirms the "time saved" estimate is acceptable or removes that tile (it is a single flag).

## Rollback
Hide the card and menu entry. Migration v3 is additive.

## Dependencies
F04 (scope names), F05 (scan events), F06 (data inventory, Forget everything). F09 extends the kept-safe tile.

## Definition of done
Tests green, screenshots in `docs/screens/F07/`, validator + gatekeeper approved.
