# Feature long list (brainstorm, 2026-11-09)

Inputs: the owner's field report, `docs/HANG_RCA.md`, the PhotoKit/Vision/MetricKit APIs verified in the installed
iOS 27.2 simulator SDK (deployment target stays iOS 26), and a quick scan of competing App Store listings. Competitor
claims are **UNVERIFIED** developer marketing ([Photo Cleanup](https://apps.apple.com/us/app/id6761067019),
[Snapsift](https://apps.apple.com/app/snapsift/id6759221222), [SnapSweep](https://apps.apple.com/us/app/-/id6759930612),
[roundup](https://ios-apps-website.web.app/blog/best-photo-cleaner-apps-iphone-2026)). The common patterns are
"on-device" claims, swipe keep/delete review, subscriptions, and full-library scans up front. Our edge is **provable
restraint**: small first scans, nothing pre-selected unless byte-identical, and an honest record of what happened.

IDs are stable; `FEATURE_ROADMAP.md` scores them.

## Scoping
- **L01 Quick Start: Recent 100** as the default first scan; results within seconds.
- **L02 Scope picker**: Recent 100 / 500 / 1,000 / Everything.
- **L03 Date range / "one month"** scope (`PHFetchOptions.predicate` on `creationDate`).
- **L04 Album scope**: one user album or smart album (`fetchAssetsInAssetCollection:options:`, verified).
- **L05 Screenshots-only scope** (`PHAssetCollectionSubtypeSmartAlbumScreenshots` = 211, verified).
- **L06 Videos-only / large-videos scope** (`SmartAlbumVideos` = 202, verified).
- **L07 Bursts-only scope** (`SmartAlbumBursts` = 207, verified).
- **L08 "Scan more" ladder**: after a scope finishes, offer the next 500 / the previous month, with a coverage ledger ("You've checked 1,240 of 8,310").
- **L09 Limited-library scope**: honor `.limited` and offer `presentLimitedLibraryPicker` (PhotosUI, verified).

## Trust / privacy
- **L10 First-run trust screens**: what we do and don't do, "nothing leaves your iPhone", no account.
- **L11 Read-only first pass**: the first scan shows results; deletion stays locked until the user opens the tray once and reads how deletion works.
- **L12 Proof of no network**: a "Privacy" screen listing what the app can't do (no network entitlement in use, no analytics SDKs), linking to Apple's App Privacy Report in Settings (text only, no deep link).
- **L13 Privacy nutrition reconciliation**: in-app text identical to the App Store "Data Not Collected" label.
- **L14 Data inventory screen**: what CleanSlate stores on the phone (index, tray, activity log, diagnostics) and its size, each with Delete.
- **L15 "Forget everything"**: one action wipes all local app data (photos untouched).
- **L16 Plain usage string**: rewrite `NSPhotoLibraryUsageDescription` (it currently says "redundant", which the word list bans).

## Safety
- **L17 Kept-safe view**: list what the app refused to suggest and why (favorites, albums, edited, shared, Live, RAW).
- **L18 Pre-delete recap** with thumbnails of keepers next to deletions (already partly in the tray).
- **L19 Delete cap per session for first-time users** (e.g. at most 50 photos in the first session).
- **L20 Recently Deleted explainer** at approval and after the receipt (text only).
- **L21 Post-delete verification**: re-fetch to confirm the photos are gone; receipt says "confirmed" vs "uncertain" (exists; surface it more).
- **L22 Protected-flag tests per new scope** (album scope must still protect album members).

## Impact / insights
- **L23 Activity log** (local, append-only, user-viewable, deletable, exportable by the user only).
- **L24 Impact dashboard**: space freed (verified), photos deleted, scans run, items kept safe, approvals undone, Apple prompts declined, time saved (labeled estimate).
- **L25 Storage composition** (local estimate by category).
- **L26 Milestone moments** ("First 1 GB freed"): calm, no gamified streaks.
- **L27 Shareable impact card** (image rendered locally, user-shared).

## Review UX
- **L28 Swipe keep/skip mode** for keeper-less lists (screenshots).
- **L29 Review the first groups while scanning** (exists, U12; make it obvious).
- **L30 Group sorting by space freed**.
- **L31 "Done for today" summary** after a session.
- **L32 Compare-mode face crops** (deferred from Step 7).

## Performance / stability
- **L33 Stability hardening**: timeouts, watchdog, bounded memory, backpressure, cancellation, resume.
- **L34 Memory governor** with device tiers (3 GB / 4 GB / 6 GB+).
- **L35 Per-asset feature-print cache** (bounded).
- **L36 Background continuation** wired (`BGContinuedProcessingTaskRequest`) for large scopes.
- **L37 Coalesced UI publishing** (≤ 2 Hz).
- **L38 Low-end performance budgets in CI** (footprint assertions on the SE simulator).

## Progress experience
- **L39 Long-operation progress card**: stage, counts, found so far, heartbeat, honest ETA, Pause/Cancel.
- **L40 Stall message**: "taking longer than usual, safe to leave", with Skip.
- **L41 Live Activity for long scans**: needs ActivityKit and an extension target. Heavy.

## Accessibility / localization / HIG
- **L42 Accessibility audits on every screen** (tray, confirm, compare, history, onboarding).
- **L43 Full String Catalog** + pseudo-language pass + plural rules.
- **L44 Second language** (e.g. Spanish). Translation quality is a human gate.
- **L45 HIG / Liquid Glass compliance pass** + feedback audit + panel review.

## Onboarding
- **L46 Permission priming** before the system prompt (exists in part).
- **L47 Limited-access path** made first-class (L09).
- **L48 Guided first review**: coach marks on the first group.

## Recovery / undo
- **L49 Undo approvals across sessions** (tray is persistent; expose "Recently approved").
- **L50 "How to restore" help** (Recently Deleted steps, text only).

## Diagnostics
- **L51 On-device diagnostics log** (rotating, no identifiers).
- **L52 Signposts + MetricKit capture** (local).
- **L53 Stall / unexpected-termination detector**.
- **L54 User-initiated diagnostics export** (ShareLink) with a preview of exactly what is in the file.

## Testing infrastructure
- **L55 Synthetic burst/overlap fixture generator** (Python, for the simulator) + `FakePhotoLibrary.burstHeavy`.
- **L56 End-to-end 100-photo test** (scan → review → approve → tray → fake delete → receipt → impact).
- **L57 Low-memory budget test on the SE simulator** (`SE-test`, iPhone SE 3rd gen device type).
