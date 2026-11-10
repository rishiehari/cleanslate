# F04: Quick Start, scoped scans (Recent 100 by default)

## Goal and story
*As a cautious first-time user, I tap one button and within seconds see what CleanSlate found in my 100 most recent
photos. If I want more, I choose it: 500, 1,000, a month, an album, screenshots, videos or everything, and I'm told
bigger scans take longer and can be paused.*

## Trust / privacy / safety
- A smaller first scan is the trust lever: fast, visibly local, and nothing to approve beyond what the user saw.
- Groups are formed **only from assets in the scope**. A copy whose twin is outside the scope is not found. Copy says
  so honestly ("Copies elsewhere in your library show up when you scan more"). No safety rule changes: commit-time
  rechecks, keeper rules, album/favorite protection and the batch cap are unchanged. An **album scope never makes album
  members deletable**: the snapshot flag `.curatedAlbum` comes from the per-asset lookup (F03), and every member of a
  user album is in a user album by definition. So album scope shows those photos as protected (Kept safe, F09).
  Smart albums (Screenshots, Videos) are not user albums.
- Album titles come from PhotoKit for display only. They are never logged (F02 allow-list) and never stored in the index.

## Device tier
Recent 100 does ≤ 100 thumbnail requests at 128 px, ≤ 300 Vision pairs and ≤ 100 full hashes, one asset at a time
(F03). Targets: **first result on screen ≤ 10 s and scan finished ≤ 30 s on tier L** (UNVERIFIED until the device gate;
simulator fake ≤ 3 s). Peak footprint ≤ tier budget (it should land far below). Scope lists are paged at 100 from
PhotoKit; no scope array is held beyond one page.

## Files
| Action | Path |
|---|---|
| create | `App/Models/ScanScope.swift` |
| modify | `App/Services/PhotoLibraryClient.swift`: `scopePage(_:offset:limit:)`, `count(of:)`, `albums()` |
| modify | `App/Services/PhotoKitLibraryClient.swift`: implement them (below) |
| modify | `App/Debug/FakePhotoLibrary.swift`: implement them; `albumsByID: [String: (title: String, members: [String])]` |
| modify | `App/Store/LibraryStore.swift`: migration v2 (`scan_scope`), `setScope(_:)`, scoped variants of the phase queries |
| modify | `App/Services/ScanEngine.swift`: `run(scope:)`; scoped inventory; every phase query restricted with `scoped: true` |
| modify | `App/Services/CleaningViewModel.swift`: `scan(scope:)`, `lastScope`, `@AppStorage("scope.last")` |
| create | `App/Views/QuickStartCard.swift` (Home, replaces the Scan button in `ScanStatusCard` when idle) |
| create | `App/Views/ScopePickerSheet.swift` |
| modify | `App/Views/ScanStatusCard.swift`, `App/Views/DashboardView.swift` |
| modify | `iOSTests/EndToEndRecent100Tests.swift` (now uses `.recent(100)`) |
| create | `iOSTests/ScanScopeTests.swift`, `UITests/QuickStartUITests.swift` |

## Types and APIs
```swift
enum ScanScope: Codable, Hashable, Sendable {
    case recent(Int)                         // 100 | 500 | 1_000
    case month(year: Int, month: Int)        // calendar month, device time zone
    case album(id: String)                   // PHAssetCollection.localIdentifier (user album)
    case screenshots, videos
    case everything
    var isLarge: Bool                        // everything, or recent > 500
    var diagnosticsName: String              // "recent100", "month", "album", … (no ids)
}
struct AlbumSummary: Identifiable, Sendable { let id: String; let title: String; let count: Int }

// PhotoLibraryClient (main actor, as today)
func scopePage(_ scope: ScanScope, offset: Int, limit: Int) -> (photos: [PhotoSnapshot], total: Int)
func count(of scope: ScanScope) -> Int
func albums() -> [AlbumSummary]               // user albums only, sorted by title
```
PhotoKit implementation (verified in the SDK headers: `fetchLimit`, `fetchAssetsInAssetCollection:options:`,
`SmartAlbumScreenshots = 211`, `SmartAlbumVideos = 202`):
- `.recent(n)`: the existing options (images + videos, hidden excluded, all bursts, `creationDate` descending) + `fetchLimit = n`.
- `.month`: + `predicate = creationDate >= start AND creationDate < end` (AND the media-type predicate).
- `.album(id)`: `PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject` → `PHAsset.fetchAssets(in:options:)` with the sort.
- `.screenshots`, `.videos`: smart album via `fetchAssetCollections(with: .smartAlbum, subtype: …)`.
- `.everything`: the existing `inventoryPage` path.
- Cache the `PHFetchResult` per scope like `inventoryFetch`. Each page is built inside `autoreleasepool`.

## Engine flow for a scope other than `.everything`
1. `store.setScope([])`, then page `scopePage` (100 at a time): `store.upsert(page)` and append ids to `scan_scope`.
   **Do not** touch `inventory.complete`, `inventory.offset` or `markUnseen` (a partial scope proves nothing about deletions).
2. If an earlier full inventory exists, still apply incremental changes first (cheap, keeps the index honest).
3. Phases 2–6 run with `scoped: true`, so every SQL query joins `scan_scope`.
4. `statistics.scope = scope`; the finish message says what was covered: "Looked through your 100 most recent photos."

## Data model: migration v2 (`PRAGMA user_version` 1 → 2)
```sql
CREATE TABLE scan_scope(asset_id TEXT PRIMARY KEY);
```
A test creates v1, migrates and checks that data is kept and `user_version == 2`.

## UI spec
**QuickStartCard** (Home, idle, no results yet):
- Title "Start small". Body: "Check your 100 most recent photos. It takes about a minute or less, and nothing is deleted."
  (The "minute" claim becomes a measured number after the device gate; until then use "Usually quick".)
- Primary `.glassProminent` button **"Check recent 100"** (`quickstart.recent100`). Secondary `.glass` button
  **"Choose what to check"** (`quickstart.choose`).
- After the first scan, the card is replaced by results plus F08's "Check more". The last scope is remembered.

**ScopePickerSheet** (`.presentationDetents([.medium, .large])`, `scope.sheet`):
- Section "Recent": rows "100 most recent", "500 most recent", "1,000 most recent", each with the live count trailing
  (`scope.option.recent100|500|1000`).
- Section "Focus": "A month…" (pushes a list of the last 24 months with counts, newest first, `scope.option.month`),
  "An album…" (pushes `albums()`, `scope.option.album`), "Screenshots" (`scope.option.screenshots`), "Videos" (`scope.option.videos`).
- Section "Everything": "All photos and videos (8,310)" (`scope.option.everything`). Footer: "Bigger checks use more
  battery and time. You can pause anytime, and CleanSlate picks up where it stopped."
- Choosing a large scope shows a one-line confirmation in the sheet ("Check all 8,310? You can pause anytime.") with
  **Start** / **Cancel** buttons. There is no system alert.
- Lists use `List` (no glass). The sheet toolbar uses glass. Dynamic Type to AX5: counts move below titles. VoiceOver
  rows read "500 most recent, 500 photos".
- Copy follows `WORD_LIST.md`: "check", "photos", "copies". Never "scan library", "assets" or "candidates".

## Sub-tasks
1. `ScanScope` + client APIs + fake implementations + unit tests per scope (ordering, limit, month bounds, album, smart albums, hidden excluded).
2. Migration v2 + `setScope` + scoped query variants + tests (scoped results never include outside ids).
3. Engine `run(scope:)` + the scoped inventory path; `.everything` unchanged; E2E Recent 100.
4. View-model `scan(scope:)` + persistence of the last scope.
5. `QuickStartCard` + `ScopePickerSheet` + month and album lists + UI tests + accessibility audit.
6. Update `ScanStatusCard` copy ("Checking your 100 most recent photos").

## Acceptance criteria
- E2E (fake, 1,000 photos; planted groups in the newest 100 **and** an exact pair at positions 400/401):
  `.recent(100)` finds exactly the newest-100 groups, **not** the 400/401 pair, with `thumbnailCalls ≤ 100` (+ Vision
  thumbnails ≤ 2 × pairs) and a wall time ≤ 3 s on the simulator.
- `.album(id)` scope: every group member that is in that album shows as protected; `SafetyPolicy` refuses it (existing rule).
- `inventory.complete` is never set by a partial scope. A later `.everything` scan does a full inventory.
- UI test: launch (fake) → tap `quickstart.recent100` → the progress element appears → the first group appears → the scan finishes.
- UI test: the picker shows counts; choosing Everything shows the confirmation line; Cancel returns without scanning.

## Test plan / validator checklist
Corner: library < 100 (it checks all, the copy says "your 37 photos"); 0 photos; a month with 0 items (row disabled
with "No photos"); an album deleted while the sheet is open (the scan reports "That album is gone", no crash); limited
access (counts reflect the limited set; the sheet says "Only photos you've shared with CleanSlate"); scope changed
mid-scan (Pause first, then the new scope); a library change during a scoped scan. Negatives: a protected copy inside the
scope stays the keeper; nothing similar is pre-marked (U4); hidden photos are never in any scope.

## Privacy review
Album titles appear only on screen. `scope.last` stores the scope kind and the album id (an opaque local id) in
UserDefaults, which already has the `CA92.1` reason (UNVERIFIED code, per the checklist). No new required-reason APIs.

## Rollback
Hide the QuickStartCard and pass `.everything` (old path intact). Migration v2 is additive and harmless if unused.

## Dependencies
F03 (bounded engine). Blocks F05 (scope names in progress copy), F06, F08.

## Definition of done
Tests green, accessibility audit on both new screens, screenshots in light/dark/AX3 under `docs/screens/F04/`,
validator + gatekeeper approved. 🧑 Device gate: Recent 100 on the owner's 17 Pro **and** one tier-L/M device; time to
first group and peak footprint logged.
