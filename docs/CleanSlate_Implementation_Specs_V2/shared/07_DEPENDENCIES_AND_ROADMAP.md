# Dependency order, feature flags, build sequence and sustainability

## 1. Existing roadmap is a prerequisite

Before starting Nxx work, inspect real HEAD and `docs/VALIDATION_LOG.md`. In the verified README snapshot, F03 physical-device scan stability was still pending; source docs already have F04–F10 and S01 (Swipe n Save) work. Do not assume unmerged branches or pending device gates are complete. New feature implementation is **serialized**: one feature, tests, device gate, independent review, then next feature. Independent researchers/QA may investigate separate features, but production code integration stays ordered.

## 2. Suggested new feature order

| Stage | Feature | Why now | Blocking gate |
|---|---|---|---|
| 0 | Existing F03/S01 and necessary scoped-scan/first-run work | stable device behavior before new heavy inference | owner physical device |
| 1 | N05 Protection rules | protects all later new recommendation surfaces | safety coordinator and migration tests |
| 2 | N04 Storage goal planner | high value using cached evidence | N05 and accurate coverage/bytes |
| 3 | N07 Screenshot intelligence | visible first-session value at low media cost | OCR hard negatives and privacy |
| 4 | N06 Mistake Finder | explainable quality signals, human review | real quality evaluation |
| 5 | N01 Moment Intelligence | calibrated multi-keeper improvement | Vision device and unique-content tests |
| 6 | N02 Similar Video | large storage opportunities | codec/device and thermal validation |
| 7 | N03 Compression Lab | highest media mutation risk | transactional creation/rollback |
| 8 | N08 Album Inbox | nondestructive utility for no-duplicate users | permissions matrix and Photos write coordinator |
| 9 | N09 Rescue Gems | positive rediscovery and retention | diversity/quality data |
| 10 | N10 Local Taste | only useful after reliable decision history | consent/privacy/holdout proof |

This is a recommended sequencing plan, not a promise of delivery time. If the build remains blocked by F03 device stability, do not push new photo decode workers to production. Research and code on a non-shipping branch can proceed while protecting the release gate.

## 3. Milestones and rough effort

A single experienced Swift/iOS developer with AI assistance, plus owner physical-device testing, can *roughly* expect:

- **Month 1–2:** resolve existing device gates, N05 rules, N04 plan engine and initial UX; achieve a trustworthy first-value flow.
- **Month 3–4:** N07 OCR screenshot packs, N06 explainable quality, plus local usability tests.
- **Month 5–6:** N01 multi-keeper moment engine, human evaluation and iPad comparison polish.
- **Month 7–9:** N02 video duplicates and N03 safe compression trials, with substantial QA/device matrix.
- **Month 9–10:** N08 Album Inbox including limited-access fallback, album mutation tests.
- **Month 10–11:** N09 Rescue Gems and user feedback study.
- **Month 11–12+:** N10 opt-in personalization, ablations and release/maintenance hardening.

This estimate excludes App Store review delays, Apple developer account administration, real dataset collection complications, and any SDK/API changes. Engineering person-days in individual files are rough design effort, not guaranteed timelines. Compression may reasonably be postponed beyond year one if validation is incomplete.

## 4. Feature flag and rollback contract

All Nxx flags are compile-time/local flags default OFF until exact feature gates pass. Flags are not remotely fetched. A rollback hides presentation and stops background work, but **never** silently removes user protection rules, committed Photos-created assets, receipts or active trays. For protection rules, rollback must continue enforcing them or block deletion altogether until data can be safely read. For compression, rollback must retain and reconcile incomplete operation journal rows, never assume the original has been deleted. For Local Taste, rollback chooses neutral ranking. Migration scripts are append-only and never undo irreversible PhotoKit changes.

## 5. Zero-subscription economics

The core logic uses Apple system frameworks (PhotoKit, Vision, AVFoundation), locally bundled code and user-device compute. There is no recurring model inference bill, database hosting, photo-storage service, third-party content moderation or telemetry ingestion. Costs still exist: Apple Developer Program membership, hardware (Mac/iPhone/iPad), QA time, code-signing/CI runner minutes, potential model licensing if optional weights are introduced, support and maintenance. **Free to every user does not imply zero cost to the developer.** Prefer first-party Apple-hosted asset packs only for later opt-in model delivery on supported OS versions, with a no-download baseline. Do not build a feature that requires recurring paid infrastructure to function.

## 6. Agent handoff sequence

For each Nxx, one PR includes:

1. Confirm source and current stage, cite the Nxx spec.
2. Record the actual baseline test/CI state and explicit pending owner gates.
3. Write failing pure safety/domain tests before implementing functionality.
4. Implement and test versioned DB migration (after current HEAD's highest version).
5. Implement independent bounded service behind protocol + fake adapter.
6. Implement iPhone feature UX; screenshots and a11y.
7. Implement iPad feature UX separately using shared domain engine; screenshots and keyboard/pointer.
8. Connect only to existing PhotoKit permission and delete/tray services.
9. Measure latency/memory/thermal/privacy; negative/race tests; unresolved device gates.
10. Update validation logs and flag status; request gatekeeper review. No next feature until approved.

## 7. Success at one year

The app remains **permanently free** with no paywall, ads, accounts or photo uploads; most users can experience at least one benefit in the first session; destructive events remain explicitly user authorized and accurately reconciled; it works in iPhone compact and iPad wide/narrow windows; photos are never represented as cloud quota reclaimed without evidence. Shipping fewer high-quality features is preferable to violating those guarantees.
