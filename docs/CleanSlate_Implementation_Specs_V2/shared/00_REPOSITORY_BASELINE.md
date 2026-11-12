# Repository baseline and integration checklist

**Observed via the connected GitHub repository on 2026-11-12:** https://github.com/rishiehari/cleanslate, default branch `main`. The repo is actively edited by multiple agents: **do not rely on a fixed branch hash from these specs**. Record `git rev-parse HEAD` and `git status --short` at each feature start. This is a source snapshot, not a claim that the codebase is fully green.

## Current source contracts — checked against actual files

| Existing code | Verified shape | Integration instruction |
|---|---|---|
| `Core/Sources/CleanSlateCore/SafetyPolicy.swift` | `evaluate(_:configuration:)`, `hardBlocked(_:)`, `validateCommit(_:currentByID:)`; requires direct evidence to a keeper | Reuse, never create a second independent deletion-eligibility function |
| `App/Services/PhotoLibraryClient.swift` | `@MainActor PhotoLibraryClient`, inventory pages, snapshots, thumbnails, digests, album membership, `delete(ids:expectedRevisions:)`, change subscription | Add narrow extension protocols/adapters; do not make unrelated services reach into `PHPhotoLibrary` |
| `App/Services/PhotoDeletionCoordinator.swift` | `commit(group:selected:manuallyReviewed:keeperIDs:)`; re-fetches, rehashes exact originals, revalidates revisions and routes to PhotoKit | NO shortcut, reimplementation, or direct `deleteAssets` call |
| `App/Store/LibraryStore.swift` | One SQLite actor with WAL and `PRAGMA user_version`; `schemaVersion = 1` in inspected content; asset, feature, digests, group, receipt tables | Migration numbers **must be allocated from actual HEAD**, not blindly copied from this package |
| `App/Services/ScanEngine.swift` | Main-actor resumable scan, candidate caps, Vision error counting, caches, `ResourceGovernor` | New classifiers are independent bounded jobs; no new full-library blocking scan on launch |
| `App/Store/DeletionTray.swift` | `TrayEntry`, `StandaloneTrayEntry`, `DeletionReceipt`, authorizations and receipts | Existing tray is only destructive-work ingress |
| `App/Services/ResourceGovernor.swift` | Thermal/low-memory/Low Power Mode checkpoint, cache-dropping hooks | Each ML/video worker must call governor checkpoints, honor cancellation and keep local-only defaults |
| `App/Models/PhotoModels.swift` | `PhotoSnapshot`, `PhotoReviewGroup`, `GroupKind`, `ScanStatistics` | Avoid overloading `GroupKind` to represent unrelated new feature state |
| `project.yml` | iOS 26 app minimum, Swift 6, universal family `1,2`, multiple scenes disabled | Both phone and tablet targets share one app binary and one mutation owner |
| `Makefile` | `core-test`, `fixtures-test`, `eval`, `lint`, `ci`, `build`, `ios-test`, `budget` | Use actual target commands, record execution results |

## Roadmap coordination and known validation risks

- The README reported **115 Core tests** on 2026-11-11. Test count changes with commits; never use that number as proof of current HEAD quality.
- `docs/FEATURE_ROADMAP.md` owns F04 Recent-100, F05 progress, F06 first-run trust, F07 local activity/impact, F08 coverage, F09 kept-safe, F10 accessibility/release. New features must compose with them and avoid duplicates.
- `docs/features/S01-swipe-n-save.md` and `docs/plans/SWIPE_N_SAVE_PLAN.md` cover two-photo swipe flows. N01 must complement this experience and not erase its review/Approve/Tray separation.
- `docs/plans/IPAD_APP_PLAN.md` outlines native iPad. `docs/plans/IPAD_IMPLEMENTATION_LOG.md` reports a **partial universal target and adaptive review workspace**; full iPad simulator/device tests remained blocked in that log. Treat iPad as partially implemented, not absent or complete.
- Repository log says F03 real-device scan stability gate remains pending. Do not declare shipping readiness from simulator success alone. Current shared tree may also have in-flight scope work that requires integration; verify before any source edit.
- `docs/PROGRESS.md` is referenced by other docs but was not retrievable at the observed repository snapshot. Confirm whether it was moved/recreated. Do not invent its contents.

## Before coding each feature

1. Verify current HEAD, uncommitted changes and active feature branch. Read `AGENTS.md`, `docs/AGENT_ROLES.md`, `docs/FEATURE_ROADMAP.md`, `docs/IMPLEMENTATION_ORDER.md`, `docs/VALIDATION_LOG.md`, `docs/PRODUCT.md`, the appropriate old feature spec, and the new Nxx file.
2. Search for already implemented abstractions. Write an ADR for any new long-lived service. Record whether the feature needs new Photos read access, write access, or background task declarations.
3. Allocate SQLite migration **after the last migration present in current HEAD**. A migration proposal in this package is a change template, not a license to overwrite concurrent migrations.
4. Add a failing unit test for the central invariant, then implement pure logic before PhotoKit-specific I/O, then UI.
5. Integrate the existing app shell and iPad adaptive shell; do not create an isolated second root view or new app target.
6. Update current roadmap/progress and validation logs only after actual tests. All GitHub branch/push/release permissions must follow the repository owner's explicit instructions and CI protections.

## Non-goals for this documentation

No SDK-private APIs, Photos database access, iCloud quota scraping, undocumented resource byte properties, cloud ML, vendor server, ad SDK, analytics SDK, subscription runtime, hidden photo upload, automatic deletion of near duplicates, or unbounded simultaneous work.
