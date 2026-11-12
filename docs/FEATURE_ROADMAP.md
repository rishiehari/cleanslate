# Feature roadmap: top 10, in build order

**2026-11-11 owner override:** Swipe n Save is now the next implementation task, ahead of F04, while F03's device gate remains PENDING. The earlier L28 deferral below is historical. See [S01](features/S01-swipe-n-save.md) and [current progress](PROGRESS.md). iPad expansion and richer swipe onboarding/calibration are planning work, not authorization to implement iPad support or automatic similar-photo deletion.

*Planner, 2026-11-09. Owner constraints applied: quality over quantity, **one feature at a time** with a stability
gate between features, low-end devices first (iPhone SE 2nd gen at 3 GB RAM is the floor iOS 26 supports; XR/XS and
the iPhone 8 cannot run iOS 26, see the note at the end), scope-first, never a frozen screen.*

## Scoring (from `FEATURE_LONGLIST.md`)
V = user value, T = trust/privacy/safety contribution, R = risk (5 = risky), E = effort (S=1, M=2, L=3).
Score = V + T − R − E. Items folded into a top-10 feature are marked → Fxx.

| ID | Item | V | T | R | E | Score | Decision |
|---|---|---|---|---|---|---|---|
| L33 | Stability hardening | 5 | 5 | 3 | 3 | 4 | **F03** |
| L34 | Memory governor, device tiers | 4 | 4 | 2 | 2 | 4 | → F03 |
| L35 | Feature-print cache | 3 | 2 | 1 | 1 | 3 | → F03 |
| L36 | Background continuation wired | 3 | 3 | 2 | 1 | 3 | → F03 |
| L37 | Coalesced publishing ≤ 2 Hz | 4 | 3 | 1 | 1 | 5 | → F03 |
| L38 | Low-end budgets in CI | 3 | 4 | 1 | 1 | 5 | → F01 |
| L51–54 | Diagnostics log, signposts, MetricKit, stall detector, export | 3 | 5 | 1 | 2 | 5 | **F02** |
| L55–57 | Fixtures, E2E 100, SE memory test | 4 | 5 | 1 | 2 | 6 | **F01** |
| L01–07 | Quick Start + scope picker (recent N, date, album, screenshots, videos, bursts) | 5 | 5 | 2 | 2 | 6 | **F04** |
| L39–40 | Progress card + stall message | 5 | 4 | 1 | 2 | 6 | **F05** |
| L10–16, L20, L46, L50 | First-run trust, read-only first pass, privacy screen, data inventory, forget everything, Recently Deleted explainer | 5 | 5 | 1 | 2 | 7 | **F06** |
| L23–24 | Activity log + Impact dashboard | 5 | 4 | 2 | 2 | 5 | **F07** |
| L08, L09, L47 | Scan more ladder + coverage ledger + limited library | 4 | 4 | 2 | 2 | 4 | **F08** |
| L17, L22 | Kept-safe view | 4 | 5 | 1 | 2 | 6 | **F09** |
| L42–45 | Step-10 completion (a11y, String Catalog, HIG, panel) | 3 | 4 | 1 | 2 | 4 | **F10** |
| L19 | First-session delete cap | 2 | 4 | 3 | 1 | 2 | not now (paternalistic; revisit after TestFlight) |
| L18, L21 | Pre-delete recap, post-delete verification | 3 | 4 | 1 | 1 | 5 | exist; polish in F10 |
| L25 | Storage composition | 3 | 1 | 2 | 2 | 0 | not now |
| L26 | Milestones | 2 | 1 | 1 | 1 | 1 | not now |
| L27 | Share card | 2 | −1 | 3 | 2 | −4 | **NOT now** (privacy optics) |
| L28 | Swipe mode | 3 | 1 | 3 | 2 | −1 | owner override 2026-11-11 → S01 |
| L29–31 | Review-while-scanning / sort / done summary | 3 | 2 | 1 | 1 | 3 | L29 → F05; L30, L31 later |
| L32 | Compare face crops | 2 | 2 | 2 | 2 | 0 | not now |
| L41 | Live Activity | 2 | 1 | 3 | 3 | −3 | NOT now (new target, more surface) |
| L44 | Second language | 2 | 1 | 2 | 2 | −1 | after launch |
| L48 | Coach marks | 2 | 2 | 1 | 1 | 2 | later |
| L49 | Recently approved | 2 | 2 | 1 | 1 | 2 | later |

## The top 10, in sequence (each one ships, stabilizes and passes its gate before the next starts)

| # | Feature | Why here | Depends on |
|---|---|---|---|
| **F01** | [Synthetic burst/overlap fixtures + E2E 100 + low-memory harness](features/F01-fixtures-e2e-harness.md) | Every later feature needs a reproducible, library-free way to prove "fast, flat memory, correct". Reproduces the hang's count explosion (H1) and the stuck-callback stall (H4) in tests first. | — |
| **F02** | [On-device diagnostics log](features/F02-diagnostics-log.md) | Lets us confirm the RCA on the owner's device and see field stalls later. Local only. Small. | F01 (tests) |
| **F03** | [Scan stability and bounded memory](features/F03-scan-stability.md) | Fixes H1–H6: timeouts, watchdog, 1–2 in flight, paged SQL, memory/thermal governor, coalesced UI, background continuation, resume. Nothing user-facing ships before this. | F01, F02 |
| **F04** | [Quick Start: scoped scans (Recent 100 default)](features/F04-scoped-scan.md) | Results in seconds; the owner's core ask. Strictly one asset at a time in this version. | F03 |
| **F05** | [Progress you can trust (never a frozen screen)](features/F05-progress-experience.md) | Stage, counts, found so far, heartbeat, honest ETA, stall message with Skip, Pause/Cancel, incremental results. | F03, F04 |
| **F06** | [First-run trust and privacy](features/F06-first-run-trust.md) | The user's first five minutes: what we do and don't do, a read-only first pass, proof, the Recently Deleted explanation, data inventory and Forget everything. | F04, F05 |
| **F07** | [Activity log + Impact](features/F07-activity-impact.md) | Shows value already delivered, on-device only. | F06 (data inventory lists it) |
| **F08** | [Scan more + coverage ledger](features/F08-scan-more-coverage.md) | Grows from 100 to everything at the user's pace, honestly ("1,240 of 8,310 checked"). | F04, F05 |
| **F09** | [Kept-safe view](features/F09-kept-safe-view.md) | Makes the safety rules visible; feeds Impact's "kept safe". | F04, F07 |
| **F10** | [Step-10 completion: accessibility, localization, HIG, panel](features/F10-step10-completion.md) | Final polish across every new and old screen, then the launch-gate review. | all |

**Merges:** (b) stability and (c) diagnostics are kept separate because diagnostics must land first to measure the
fix. The owner's progress requirement is its own feature (F05) so it gets its own UI tests. Recently Deleted /
recovery is folded into F06.

## Deliberately NOT now
- Near-duplicate pre-selection or any ML change (`ML_GATE.md` stays OFF).
- Album transfer (Step 8.4); albums stay always-protected.
- Anything networked: accounts, cloud sync, remote config, crash SDKs, analytics. MetricKit payloads are stored locally only.
- Live Activities, widgets, App Intents/Shortcuts, notifications. Each adds a surface and a target.
- Streaks and share cards. Owner-requested Swipe n Save uses staged choices and the normal approval/tray path (S01).
- Wider opt-in iCloud original downloads (keep the existing budgeted path unchanged).
- Faster full-library scans (parallel Vision, GPU batching). Do 100 photos well first. Optimize after F08 with data from F02.
- Subscriptions / paywall.
- A second language (after launch; the String Catalog lands in F10).
- Lowering the minimum OS. iOS 26 runs on the A13 (iPhone 11, SE 2nd gen) and newer. XR, XS and 8 cannot run it.
  Supporting them would need iOS 16–18 support, which is a separate product decision (owner) and is **not recommended**:
  it doubles the visual system for a small, shrinking audience.

## Device floor note
Supported low end on iOS 26: **iPhone SE (2nd gen), 3 GB RAM**; iPhone 11 / SE (3rd gen) / 12 at 4 GB. These are the
memory budget tiers used in every spec (UNVERIFIED RAM figures from public teardowns; the app detects the tier at
runtime with `ProcessInfo.physicalMemory`, verified in the SDK). Compatibility per secondary sources
([TechRadar](https://www.techradar.com/phones/ios/ios-26-compatibility-does-your-iphone-support-it-heres-the-full-list-of-supported-devices),
[9to5Mac](https://9to5mac.com/2025/09/15/ios-26-supports-these-recent-iphones-but-drops-three-models/)). Confirm on
support.apple.com before quoting it in metadata.

### Shared device-tier budgets (every spec refers to these)
| Tier | Detect | Peak phys_footprint during any scan | In-flight assets | Fingerprint thumb | Vision thumb |
|---|---|---|---|---|---|
| L (≤ 3 GB) | `physicalMemory < 3.5 GB` | **≤ 120 MB** | 1 | 128 px | 256 px |
| M (4 GB) | `< 5.5 GB` | **≤ 160 MB** | 1 (2 when thermal is nominal) | 128 px | 320 px |
| H (≥ 6 GB) | else | ≤ 200 MB | 2 | 128 px | 384 px |

The fingerprint size is the same on every tier, so hashes are comparable. Changing it from 280 px means `ScanEngine.featureVersion` goes to 2 (F03).

The footprint must stay **flat**: its growth from scope 100 to scope 10,000 (fake library, thumbnails ON) must be
≤ 15 MB. Measured by `phys_footprint` (`TASK_VM_INFO`, verified in `mach/task_info.h`) sampled every 100 ms in tests.
On devices it is measured with Instruments Allocations/VM Tracker and `MXMemoryMetric.peakMemoryUsage`. The simulator
does not enforce device memory limits, so the test asserts the budget itself; a device run on 3 GB / 4 GB hardware is
a 🧑 human gate.
