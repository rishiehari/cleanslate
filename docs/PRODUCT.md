# CleanSlate — Product definition

*Status: default positioning adopted by the executing agent on 2026-11-05; owner confirmation pending (see `VALIDATION_LOG.md`, Step 2).*

## One-line promise
**CleanSlate finds the copies. You decide.** Nothing is deleted until you approve it in CleanSlate and confirm it in Apple's own prompt.

## Who it is for
Someone with a large photo library (50k–250k items), iCloud Photos on, a "storage almost full" warning, and low tolerance for deleting a memory by mistake.

## Where we fit next to Apple Photos
Apple's Photos app (Collections → Utilities → **Duplicates**) already finds exact and near-exact duplicates and can *merge* them, keeping the best quality and combining details. PhotoKit does not expose merge, so CleanSlate cannot match that for exact copies. We therefore:
- Tell users about the Duplicates album during onboarding (text only, no deep link).
- Keep byte-verified exact copies as one feature among several.
- Compete where Photos does not: **bursts and similar shots, videos, screenshots and screen recordings, large files, and an honest storage receipt**.

## Problems ranked by storage impact (hypothesis, to be validated in Step 9 / TestFlight)
1. Large and duplicate videos.
2. Bursts and near-identical shots.
3. Old screenshots and screen recordings.
4. Exact copies (imports, message-app saves, "Duplicate" taps).

## Feature categories
| Category | Selection model | Preselected? |
|---|---|---|
| Exact copies | Keep one, remove byte-identical copies | Yes (the copies), user approves |
| Similar & bursts | Keep one or more, user picks what to remove | **Never** |
| Videos (duplicates, similar, large) | As above, or standalone | Exact only |
| Screenshots & recordings | Standalone, user selects | **Never** |
| Large files | Standalone, user selects | **Never** |
| Receipts / History | Read-only record of what was deleted | n/a |

## Interaction model: Review → Approve → Tray → Delete
Approving moves photos into a **Deletion tray**; it never deletes. The tray's summary sheet, then Apple's system prompt, are the only paths to deletion.

## Non-goals
No cloud or accounts. No ads, tracking, subscriptions or analytics. No automatic deletion of anything that is not byte-identical. No merging of photo metadata. Native iPad layouts are in implementation; release requires the separate iPad validation gates. No claims of exhaustive duplicate detection.

**2026-11-11 planning update:** the owner requested an iPad expansion plan and a detailed Swipe n Save interaction,
onboarding and calibration plan. iPad implementation was authorized later that day; the first universal-target and adaptive-layout increment is underway. Swipe n Save's initial implementation reuses
existing directly compared similar pairs; choices are explicit and approval still only adds to the tray. Personalization
is planning-only and does not change the [ML gate](ML_GATE.md) or authorize automatic deletion.

## Success metrics
- Verified bytes recovered per session (receipts).
- Harmful-deletion reports: **0** (hard launch gate).
- Review throughput (groups per minute) in hallway tests.
- Crash-free sessions ≥ 99.5% in TestFlight.

## Platform decision
Minimum iOS **26** (iPhone 11 and newer): Liquid Glass and `BGContinuedProcessingTask` require it, and supporting iOS 18 would mean maintaining two visual systems. Reversible: if the owner prefers iOS 18, glass uses get `#available` fallbacks (Step 2B notes).
