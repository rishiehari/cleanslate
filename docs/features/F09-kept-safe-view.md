# F09: Kept safe, showing what CleanSlate refused to suggest

## Goal and story
*I can see the photos CleanSlate deliberately left alone in my last check (favorites, photos in my albums, edited
photos, shared items, burst picks and so on) and why. That shows me the rules protect what I care about.*

## Trust / privacy / safety
- **Read-only screen.** No select, approve or delete affordance exists on it. A UI test asserts this.
- It mirrors, and never redefines, the existing protection rules (`PreservationFlag` in `Core/Sources/CleanSlateCore/Models.swift:5-7`,
  enforced by `SafetyPolicy`). The view **reads** flags; it never decides deletability.
- Copy never nudges users to remove protections. A neutral "Why" line per reason is fine. There is **no** "unprotect" call to action.

## Device tier
Computed at scan end from data already in memory (found groups) plus **one SQL count/page** over in-scope assets with
`flags <> ''`. The list pages 60 at a time with small thumbnails (≤ 160 px) through the existing `PhotoThumbnailView`,
and the cache is cleared on disappear. No extra PhotoKit snapshot calls.

## Files
| Action | Path |
|---|---|
| create | `App/Models/KeptSafeReason.swift`: maps `PreservationFlag` → `KeptSafeReason` (user wording, SF Symbol, order) |
| modify | `App/Store/LibraryStore.swift`: `protectedInScope(reason flag: String?, afterRowID:limit:) -> [PhotoSnapshot]`, `protectedCountsInScope() -> [String: Int]` (uses `scan_scope`; no migration, since flags are already stored) |
| modify | `App/Services/CleaningViewModel.swift`: `keptSafeCounts: KeptSafeCounts` published at scan end (feeds F07's `checkFinished`) |
| create | `App/Views/KeptSafeView.swift`, `App/Views/KeptSafeReasonList.swift` |
| modify | `App/Views/DashboardView.swift`: a "Kept safe: 55" row under the categories (`keptsafe.row`) |
| modify | `App/Views/ImpactView.swift` (F07): the kept-safe tile links here |
| create | `iOSTests/KeptSafeTests.swift`, `UITests/KeptSafeUITests.swift` |

## Types
```swift
enum KeptSafeReason: String, CaseIterable, Sendable {
    case favorite, album, edited, shared, burstPick, livePhoto, raw, cinematic, spatial, hidden, incomplete, uncertain
    init(_ flag: PreservationFlag)   // curatedAlbum→album, userBurstPick→burstPick, incompleteResources→incomplete,
                                     // unknownOwnership/uncertainMetadata→uncertain, cinematicVideo→cinematic, spatialMedia→spatial
    var title: String                // "Favorites", "In your albums", "Edited", "Shared with you", "Burst picks", …
    var why: String                  // "You marked these as favorites, so CleanSlate never suggests deleting them."
    var symbol: String               // heart.fill, rectangle.stack, slider.horizontal.3, person.2, star.square, livephoto, …
}
```
A photo with several flags is listed under its **first** reason by `allCases` order and counted once in the total.
Hidden photos are excluded from scopes (F04), so `hidden` normally shows 0 and its row is omitted.

## UI spec
**KeptSafeView** (`keptsafe.screen`): title "Kept safe". Header: "In your last check, CleanSlate left 55 photos alone.
These are never suggested for deleting." Then one section per reason with a count (`keptsafe.reason.<rawValue>`),
showing the `why` line and a horizontal strip of up to 12 thumbnails, plus "Show all" (`keptsafe.showall.<rawValue>`),
which pushes a paged grid. Tapping a thumbnail opens the existing read-only peek (no Keep/Delete toggles). Empty state
(`ContentStateView`): "Nothing needed protecting in this check." VoiceOver reads each thumbnail as "Favorite photo, 3 of 38".
No glass on content. AX5: the strips become vertical lists.

## Sub-tasks
1. `KeptSafeReason` mapping + Core-free unit tests (every `PreservationFlag` case is mapped; adding a flag fails the test until it is mapped).
2. Store queries + `keptSafeCounts` at scan end + feed into F07 `checkFinished`.
3. `KeptSafeView` + reason list + paged grid + peek reuse.
4. Home row + Impact link + UI tests + accessibility audit.

## Acceptance criteria
- Fake Recent 100 (F01: favorite copy, album member, edited, shared): the screen shows those 4 under the right reasons;
  counts match `protectedCountsInScope()`.
- UI test: the screen hierarchy contains **no** buttons labeled Approve, Delete or Select, and the tray count is unchanged after interacting.
- Exhaustiveness test: `PreservationFlag.allCases` (add `CaseIterable` in Core if missing; this is additive and not a
  safety-test edit) all map to a reason.
- `performAccessibilityAudit()` passes, including at AX5.

## Test plan / validator checklist
Corner: 0 protected; 2,000 protected (paging, flat memory); a photo with 3 flags (counted once); an album scope (every
member under "In your albums"); limited access. Negative: a protected photo can't be toggled from the peek; a flag
change after the scan (favorite added) shows on the next check, and the tray recheck still guards deletion.

## Privacy review
Thumbnails appear on screen only. Nothing is stored beyond the existing flags column.

## Rollback
Remove the Home row; the view is self-contained.

## Dependencies
F04 (`scan_scope`), F07 (kept-safe counts in activity). Independent of F08.

## Definition of done
Tests green, screenshots, validator + gatekeeper approved.
