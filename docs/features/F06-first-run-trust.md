# F06: First-run trust and privacy

## Goal and story
*Before I give a new app access to my photos, I want to know what it will and won't do. In my first minutes I see
results without risk, I learn exactly how deleting works and how to get a photo back, and I can see and erase
everything the app keeps on my phone.*

## Trust / privacy / safety
- **Read-only first pass:** the first results are a preview. The approval bar is replaced by "Ready to choose?" until
  the person has read *How deleting works* once. This is a UI gate on top of the unchanged
  Review → Approve → Tray → Apple prompt path. It adds a step; it removes none.
- Claims must be literally true. "Nothing leaves your iPhone" is true for CleanSlate's own code. The opt-in iCloud
  originals feature makes **Photos** download the user's own originals from iCloud. Copy must say that wherever the
  privacy claim appears.
- "Forget everything" deletes only CleanSlate's own files and settings. It cannot touch photos (no PhotoKit write calls).

## Device tier
Text screens only. The data-inventory screen computes file sizes once on appear (off the main actor). No impact on scan memory.

## Files
| Action | Path |
|---|---|
| modify | `App/Views/OnboardingView.swift`: 4 pages (below) + permission priming page |
| create | `App/Views/Trust/PrivacyView.swift` ("Your privacy") |
| create | `App/Views/Trust/DataOnPhoneView.swift` ("Data on this iPhone" + Forget everything) |
| create | `App/Views/Trust/HowDeletingWorksSheet.swift` |
| create | `App/Views/Trust/HowToRecoverSheet.swift` |
| create | `App/Services/TrustState.swift`: `@MainActor final class TrustState: ObservableObject` (`hasReadHowDeletingWorks`, `firstScanCompleted`), UserDefaults keys `trust.readDeleting.v1`, `trust.firstScan.v1` |
| create | `App/Services/LocalDataInventory.swift`: lists the stores and their sizes; `forgetEverything()` |
| modify | `App/Views/ReviewGroupView.swift` / `App/DesignSystem/Components/ApprovalBar.swift`: preview gate |
| modify | `App/Views/StandaloneListView.swift`: same gate on its approve action |
| modify | `App/Views/CategoryGroupsView.swift`: the "Approve all N copies" entry (opens `ApproveAllSheet`) is gated the same way |
| modify | `App/Views/ReceiptView.swift`, `App/Views/HistoryView.swift`: "How to get photos back" link |
| modify | `App/Views/DashboardView.swift`: menu items "Your privacy", "Data on this iPhone" |
| modify | `project.yml`: `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` |
| modify | `site/privacy.html`: same claims, same words (draft; the owner publishes) |
| create | `UITests/TrustUITests.swift`, `iOSTests/LocalDataInventoryTests.swift` |

## Types
```swift
struct LocalDataItem: Identifiable, Sendable { let id: Kind; let bytes: Int64?; let summary: String
    enum Kind: String, Sendable { case scanIndex, tray, activityLog, diagnostics, labels, settings } }
@MainActor final class LocalDataInventory {
    init(model: CleaningViewModel, diagnostics: DiagnosticsLog?, activity: ActivityLog?)   // activity is nil until F07
    func items() async -> [LocalDataItem]
    func delete(_ kind: LocalDataItem.Kind) async throws
    func forgetEverything() async throws   // refuses while scanning or deleting (throws .busy)
}
```
`forgetEverything` calls: `store.reset()`, `tray.clear()`, `DiagnosticsLog.deleteAll()`, `ActivityLog.deleteAll()`
(after F07), the `LabelStore` reset, and removes CleanSlate's UserDefaults keys **except** `onboarding.seen.v1`.

## UI spec and copy (word list respected)
**Onboarding** (`onboarding.pages`):
1. `lock.shield`: "Everything stays on this iPhone". "CleanSlate checks your photos right here. No account, no ads,
   no tracking, and CleanSlate has no servers to send anything to." Link: "Your privacy" (`onboarding.privacy`).
2. `hand.raised`: "You decide, twice". "Nothing is deleted until you approve it here and confirm it in Apple's own
   prompt. Deleted photos stay in Recently Deleted for 30 days. With iCloud Photos on, they're removed from your other devices too."
3. `scope`: "Start small". "Your first check looks at your 100 most recent photos. You'll see what it finds before anything can be deleted."
4. `square.on.square`: the existing Apple Duplicates page.
5. Permission priming: "Next, iOS asks to let CleanSlate see your photos. *Allow Full Access* lets it check everything.
   *Limit Access* lets you pick photos." Button "Continue" (`onboarding.allow`) triggers `requestAccess()`.

**Preview gate:** while `!hasReadHowDeletingWorks`, the approval bar (`approval.preview`) shows "Ready to choose? See
how deleting works" (`.glassProminent`). It opens `HowDeletingWorksSheet` (`trust.deleting`): three numbered steps
(Approve adds to your tray · You delete from the tray · Apple asks you to confirm), plus "Deleted photos stay in
Recently Deleted for 30 days." and "How to get photos back". Button **Got it** (`trust.deleting.ok`) sets the flag. The
normal Approve/Skip bar then appears. Skip stays available in preview.

**HowToRecoverSheet** (`trust.recover`): text-only steps for restoring from Recently Deleted in Photos (exact menu
path **UNVERIFIED** for iOS 26; the owner checks it on a device) and "After 30 days, or after you empty Recently
Deleted, photos can't be recovered." No deep links (`photos-redirect://` is forbidden by §0.1.5).

**PrivacyView** (`trust.privacy`): two lists, "CleanSlate does" (checks photos on this iPhone; saves a small index to
make the next check faster; keeps a private activity record you can delete) and "CleanSlate never does" (upload photos;
collect analytics; show ads; need an account; delete without your OK). Then "Check it yourself": "Turn on Airplane Mode:
CleanSlate works the same." and "The App Store listing says *Data Not Collected*." and "In Settings → Privacy &
Security → App Privacy Report, you can see which apps used the network." (path **UNVERIFIED**; the owner confirms).
iCloud note: "If you turn on *iCloud originals*, Photos downloads your own originals from iCloud so they can be
checked. CleanSlate itself still sends nothing."

**DataOnPhoneView** (`trust.data`): a row per `LocalDataItem` with its size and **Delete** (`trust.data.delete.<kind>`),
then **Forget everything** (`trust.data.forget`, destructive, with an alert: "Forget everything? CleanSlate removes its
saved checks, tray, activity and diagnostics. Your photos aren't touched.").

**Usage string:** "CleanSlate looks at your photos on this iPhone to find copies. Nothing leaves your phone, and nothing
is deleted without your OK." (removes the banned word "redundant").

All screens: `List`/`ScrollView` content without glass; Dynamic Type to AX5; every link has a button trait; no color-only meaning.

## Sub-tasks
1. `TrustState` + preview gate on group review and standalone lists + unit/UI tests.
2. `HowDeletingWorksSheet` + `HowToRecoverSheet`, linked from the gate, receipt and history.
3. Onboarding rewrite + priming page + usage string.
4. `PrivacyView`.
5. `LocalDataInventory` + `DataOnPhoneView` + Forget everything + tests.
6. `site/privacy.html` sync + accessibility audits + screenshots.

## Acceptance criteria
- UI test: fresh install (`-resetOnboarding`, fake library) → 5 onboarding pages → Recent 100 → open a group → **no Approve button**, `approval.preview` present → read the sheet → Approve present → approve works → tray badge = N.
- UI test: Forget everything → tray badge 0, History empty, Diagnostics empty, `debug.probe` shows `assets` unchanged and `deleteCalls=0`.
- Unit: `forgetEverything()` throws `.busy` while `isScanning` or `tray.isDeleting`.
- `grep -n redundant project.yml` gives nothing. `performAccessibilityAudit()` passes on all 5 new screens and the onboarding pages.
- Existing UI tests that approve on a seeded model launch with `-trustReadDeleting` (a DEBUG argument that sets the flag), so they keep passing unedited apart from that launch argument.

## Test plan / validator checklist
Negatives: the gate can't be bypassed by Approve All (`ApproveAllSheet` respects the gate) or by standalone multi-select;
Forget everything during a scan is refused; Forget everything removes the in-memory tray entries too. Corner: limited
access (the priming page explains Limit Access; Home already shows the limited notice); permission denied after
onboarding; AX5 on every page; VoiceOver reading order on the onboarding pages.

## Privacy review
This feature *is* the privacy review surface. 🧑 The owner signs off the claims text, verifies the two UNVERIFIED Settings
paths on a device, and confirms the App Store "Data Not Collected" answer matches.

## Rollback
The flag `trust.previewGate` (default on) can disable the gate. The other screens are additive.

## Dependencies
F04 (Recent 100 wording), F05 (first-scan experience), F02 (diagnostics delete). F07 plugs into `LocalDataInventory`.

## Definition of done
Tests green, the owner approves the copy (🧑), screenshots in `docs/screens/F06/`, validator + gatekeeper approved.
