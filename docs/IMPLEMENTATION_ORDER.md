# Implementation order: F01 → F10

*Planner, 2026-11-09. Read with `FEATURE_ROADMAP.md` (scores, budgets) and `features/Fxx-*.md` (specs). §0 of
`EXECUTION_PLAN.md` applies to every commit.*

## Principle: one feature at a time, each complete and stable before the next
The owner's rule is **quality over quantity**. Features are built **strictly sequentially**: there is no parallel
feature work, and no feature starts until the previous one has passed its **stability gate** (below). Inside a feature,
sub-tasks are one commit each and are also done in order. Fewer, deeper features: if a feature runs long, cut its
scope rather than overlap it with the next one.

The only parallelism allowed is **within** a feature's flow, as in `AGENT_ROLES.md`: the validator can run gates while
the executor writes docs, and screenshots can be captured while the gatekeeper reads the diff.

## Sequence and why
```
F01 fixtures/E2E/budget harness ─► F02 diagnostics ─► F03 stability (hang fix) ─► F04 Quick Start scopes
     (test infra, no UX change)      (measure)           (🧑 device gate)            (🧑 device gate)
  ─► F05 progress experience ─► F06 first-run trust ─► F07 activity + impact ─► F08 check more + coverage
  ─► F09 kept safe ─► F10 Step-10 completion ─► TestFlight (existing Step 10.6, 🧑)
```
- **Shared infrastructure first:** F01 (fake-library scenarios, `VisualAnalyzing` seam, `FootprintSampler`,
  `make budget`) and F02 (`DiagnosticsLog`, signposts, `DeviceTier`, `MemoryProbe`) are used by every later feature.
- **Nothing user-facing ships before F03.** No build with the old full-library scan goes to anyone else.
- **Trust before value:** scope (F04), visible progress (F05) and the first-run promises (F06) come before Impact (F07)
  and growth (F08).

## Stability gate (between every pair of features)
A feature is "done" only when **all** of these are true and logged in `VALIDATION_LOG.md`:
1. `make ci` green (core, fixtures, eval, lint, build, iOS unit + UI). A simulator that hangs is reported, not passed.
2. `make budget` green on **SE-test** and the default simulator. Peak `phys_footprint` is within the tier budget, and
   growth from scope 100 to 10,000 is ≤ 15 MB (from F03 on; F01/F02 record the baseline).
3. Main-thread watchdog: no block > 250 ms during the 10,000-photo fake scan (from F03 on).
4. `HangReproTests`, `EndToEndRecent100Tests` and every `SafetyPolicyTests` assertion pass. No safety test is edited.
5. `scripts/check_policy_separation.sh` passes. `grep -rn "deleteAssets" App` gives 1. No new `URLSession` /
   `isNetworkAccessAllowed = true`.
6. Validator report PASS-TO-GATE (with its negative and corner-case list), and gatekeeper **APPROVE**.
7. For UI features: `performAccessibilityAudit()` on the new screens, and screenshots (light/dark/AX3) in `docs/screens/Fxx/`.
8. A soak: the fake 10,000-photo scan run 3 times back to back in one test process without footprint growth over
   10 MB (a leak check).
9. Any 🧑 device gate listed for the feature is done, or explicitly waived by the owner in the log.

## Risk gates and human gates
| After | Gate | Who | Blocking? |
|---|---|---|---|
| F02 | Optional: owner runs the **current** engine + diagnostics on the 17 Pro and shares the file, to confirm H1–H4 | 🧑 owner | No (recommended) |
| F03 | **Device read-only scan**: 17 Pro + one tier-L/M phone (SE 2/3 or iPhone 11) on a disposable or owner-approved library ≥ 7,000. Diagnostics file + Instruments Hangs/Allocations. Pass = no stall without a message, footprint ≤ tier budget, Pause ≤ 2 s. | 🧑 owner | **Yes** |
| F03 | `/code-review high` on the F03 diff (riskiest refactor) | orchestrator | Yes |
| F04 | Recent 100 on device: time to first group, total time, footprint | 🧑 owner | **Yes** |
| F06 | Owner signs off the privacy claims and verifies the 2 Settings paths and the Recently Deleted path on device | 🧑 owner | **Yes** |
| F07 | Owner keeps or drops the "time saved" estimate tile | 🧑 owner | No (flag) |
| F08 | Ladder to 1,000 on a tier-L/M device | 🧑 owner | Yes |
| F10 | Hallway test (2–3 people, SE-class device, fake data); privacy-manifest codes and export compliance verified against Apple pages | 🧑 owner | **Yes** |
| any | Any change to `SafetyPolicy`, preservation flags or the deletion path: **none planned**. If one becomes necessary, stop and escalate. | 🧑 owner | Yes |

## Migrations (LibraryStore `PRAGMA user_version`)
| Version | Feature | Change |
|---|---|---|
| 2 | F04 | `scan_scope` |
| 3 | F07 | `activity` (+ index); `reset()` keeps it |
| 4 | F08 | `features.featureprint`, `features.quality_json`, `checked`, `compared_pairs` |
Each has a "create previous version → migrate → data intact" test. F03 bumps `ScanEngine.featureVersion` to 2 (no schema change).

## Low-end device discipline (applies to every feature)
- Concurrency is **1 asset in flight** until a later measured change (F03).
- Thumbnails: 128 px fingerprints; Vision 256/320/384 px by tier.
- `autoreleasepool` per asset for synchronous image work. Never keep a `UIImage` past its iteration.
- Page from SQLite (≤ 500 rows) with keyset cursors. No whole-library arrays.
- `ResourceGovernor` reacts to memory warnings, `os_proc_available_memory()`, thermal state and Low Power Mode by
  pausing and shrinking batches, and always says why (F05).
- Every long operation is cancellable within 2 s and resumable.
- Measure: `FootprintSampler` in tests (`make budget`, SE-test); Instruments Allocations/VM Tracker and
  `MXMemoryMetric.peakMemoryUsage` on devices; heartbeat lines in the F02 log.

## Estimated size (executor sessions, for planning only)
F01 M · F02 M · F03 L (11 commits) · F04 M · F05 M · F06 M · F07 M · F08 M · F09 S · F10 M–L.

## Owner decisions needed before or during this sequence
1. The **headline text** on screen when the scan "hung", and the library size. This confirms H1a vs H1b in minutes.
2. Approve **Recent 100 including videos and screenshots** as the default scope (recommended: yes, it is "the newest
   100 items", which matches the Photos grid).
3. Keep iOS 26 as the minimum (recommended). XR, XS and 8 cannot be supported without a separate iOS 16–18 build.
4. Keep or drop the "time saved" estimate (F07).
5. A device for tier-L/M testing (an SE 2nd/3rd gen or iPhone 11) and a disposable library for the F03/F04/F08 gates.
