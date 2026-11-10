# Hang RCA: "Scan All" stalls after ~7,000 photos (iPhone 17 Pro)

*Planner, 2026-11-09, against commit `081ec65`. Analysis from code only: there is no crash report, no jetsam entry
and no MetricKit data. Every hypothesis below needs device confirmation before it counts as "the cause".*

## 0. What the user saw, and what that tells us
- The only number on Home during a scan is `"\(photosEnumerated) photos checked"` (`App/Views/ScanStatusCard.swift:49-53`).
  `photosEnumerated` is set **once**, after the inventory finishes (`App/Services/ScanEngine.swift:52-53`), and never
  changes after that. So "stuck at ~7,000" most likely means **the inventory finished** (the library has about 7,000
  items) and the scan stalled in a **later** phase, with a number that was never going to move.
- The progress bar covers phases 4–6 in the 0.65→1.0 band and updates every 5–10 items (`ScanEngine.swift:258, 292, 338, 397`).
  For long phases the bar looks frozen.
- **Owner question (cheap and decisive): what did the headline say when it "hung"?** "Checking the original files" means H1a,
  "Comparing similar shots" means H1b, "Finding your photos" means H2/H3 during inventory.

## 1. Ranked hypotheses

| # | Hypothesis | Likelihood | Kind |
|---|---|---|---|
| H1 | Super-linear, sequential late-phase work sized for a 250k cap, with no visible progress | **Very high** | perceived hang (minutes to hours) |
| H2 | No background continuation and no idle-timer handling: auto-lock suspends the scan | **High** (contributing) | real stop |
| H3 | Main-actor saturation and SwiftUI re-render storm (O(G²) work per found group) | High (contributing; worse on low-end) | real UI hang |
| H4 | A PhotoKit callback that never fires, so a continuation is never resumed (no timeouts) | Medium | permanent stall, Pause ineffective |
| H5 | Memory pressure / thrash (no autoreleasepool, whole-library arrays, uncached Vision) | Medium on low-end, low on 17 Pro | slowdown, or jetsam on 3 GB devices |
| H6 | Thermal pause loop (`.serious` waits up to 10 min, repeatedly) | Low–medium | visible pause, easy to mistake for a hang |
| H7 | SQLite / LibraryStore contention | Low | — |

### H1. Late phases do far more work than the library size suggests, sequentially and almost invisibly
**H1a: full-original hashing of every near-pair member.** `verifyExactCopies` enqueues exact-bucket members **and both
members of every near/moment pair** (`ScanEngine.swift:233-234`) for full-resource SHA-256, capped at 4,000 assets
(`:27, :235-239`). Each asset streams **every** resource (photo, paired Live video, adjustments) through
`PHAssetResourceManager.requestData` one at a time (`PhotoKitLibraryClient.swift:225-252`). On a 7k burst-heavy
library, 4,000 assets × 2–3 resources × tens to hundreds of ms works out to **10–60 min** (UNVERIFIED estimate) under the
headline "Checking the original files", with the counter fixed at 7,000.

**H1b: the Vision phase.** `compareSimilarPairs` handles up to **30,000 pairs** (`:30, :349`). Per pair it requests two
512-px thumbnails and runs **six Vision requests** (2 feature prints, 2 face-quality, 2 aesthetics; `:359-386`), with
**no per-asset cache**, so a photo in 40 pairs gets printed 40 times. `momentPairs` makes all pairs within 12 s, up to
256 per bucket (`LibraryStore.swift:401-409`): one 30-shot burst alone gives 435 pairs. `buildReviewSets` also runs
512-px thumbnails plus 2 Vision requests for **every** photo in every burst/run (`:312-325`). At ~0.15–0.3 s per pair
(UNVERIFIED), 30k pairs takes **1.5–2.5 h** on an A19 Pro and 3–5× that on an A13.

*Why most likely:* it fits "stuck at ~7,000" exactly (inventory done, number frozen). It needs no bug, only scale. And
the scale tests turn thumbnails off (`iOSTests/ScaleTests.swift:23`, `disableThumbnails = true`), so the simulator
never exercised phases 4–6 at volume. The 252k "PASS" says nothing about this.

**Confirm on device:** `os_signpost` intervals per phase and per asset (F02). In Instruments, use *Points of Interest*,
*Time Profiler* and *os_signpost* together. Record `pairs.count`, `order.count` and the items done per minute in the local
diagnostics log. If the phase interval is open for more than 10 min while per-item signposts keep arriving, H1 is
confirmed.

**Fix (F03 + F04):** scoped scans (Recent 100 by default) bound every phase by scope. Pairs are only generated *within*
the scope. Feature prints are cached per asset per scan (bounded LRU of 64). Full-original hashing applies **only to
exact-bucket members**; near pairs never trigger full hashing. Quality signals for review sets come from a single
cached pass. Per-phase item caps are derived from scope size. Progress counts the units of the current phase
("Comparing 212 of 1,040").

### H2. The scan silently stops when the phone auto-locks or the user switches apps
`BackgroundScanning.register()`, `requestContinuedProcessing()` and `scheduleOvernight()` have **zero call sites**
(`grep -rn` over `App/`). The Info.plist declares the identifiers (`project.yml:31-35`), but the handlers are never
registered. Nothing sets `UIApplication.shared.isIdleTimerDisabled`. A user who puts the phone down during a 30-minute
phase gets auto-lock in 30 s to 5 min, then the app is suspended and the scan stops. When they come back it continues,
but by then it "hung".

**Confirm:** a `scenePhase` transition entry in the diagnostics log (F02) next to the last per-item heartbeat.
**Fix (F03):** wire `BackgroundScanning.register()` in `App.init`, and on Start request continued processing for
scopes > 500. Never disable the idle timer silently (battery, trust). Instead, F05 shows "Safe to leave: CleanSlate
picks up where it stopped". Also checkpoint on `scenePhase == .background`.

### H3. Main-actor saturation and re-render storms
- The whole engine is `@MainActor` (`ScanEngine.swift:21`). So is the library client (`PhotoLibraryClient.swift:9`). The
  following synchronous CPU work runs on the main thread between awaits:
  - `sharpnessAndExposure` (a 64×64 redraw plus loops) per photo (`ScanEngine.swift:317, :379-380`).
  - Building `Set(near.pairs).union(moments)` from up to 400k pairs, plus `flatMap` and `filter` (`:205-211`).
  - `userAlbumAssetIDs()` enumerates **every asset of every album** synchronously (`PhotoKitLibraryClient.swift:73-80`).
  - `inventoryPage` builds 1,000 snapshots per call, each calling `PHAssetResource.assetResources(for:)`
    synchronously (`:118-122, :175`). That is seconds per page.
- `scanUpdate` mutates the `@Published statistics` per asset (`ScanEngine.swift:250, 256`). Each mutation fires
  `objectWillChange`, which re-evaluates `DashboardView`. Its category cards call `model.count(in:)` and
  `verifiedBytes(in:)`, which filter every group for every category (`CleaningViewModel.swift:168-211`).
- `groups` has a `didSet` that runs `recomputeStandalone()` (over all standalone items × categories) **and**
  `rebuildMembership()` (over all groups) **on every append of 5 groups** (`CleaningViewModel.swift:11, 326-330`). That
  is O(G²) over a scan.
- **Confirm:** the Instruments *Hangs* instrument, `MXHangDiagnostic` (MetricKit, iOS 14+, verified in SDK headers),
  and SwiftUI *View Body* counts. A main-thread run-loop watchdog (F02) logs any main-thread block over 250 ms with its
  phase.
- **Fix (F03):** coalesce `statistics`/`progress` publishing to ≤ 2 Hz through a `ScanProgressReporter` that is not
  `@Published` per item. Make group appends incremental (update the membership index and standalone cache by delta).
  Move pure CPU work (`sharpnessAndExposure`, hashing, pair set-building) to `Task.detached`. Inventory pages become
  100 items inside `autoreleasepool`. Album membership is computed lazily per scope (only the scope's ids:
  `fetchAssetCollectionsContaining` for ≤ the scope size, or one album pass capped and yielded every 200 assets).

### H4. A continuation that is never resumed
- `thumbnail()` (`PhotoKitLibraryClient.swift:205-222`), `digest()` (`:237-252`) and `verifiedSize()` (`:48-68`)
  wrap PhotoKit callbacks in continuations with **no timeout and no cancellation handler**. The SDK header says:
  *"If the request is cancelled, resultHandler may not be called at all"* (`PHImageManager.h:180`, iOS 27.2 SDK).
- `computeFeatures` awaits a `withTaskGroup` (`ScanEngine.swift:167-179`). **One** stuck child blocks the batch forever.
  Pause calls `scanTask.cancel()`, but cancellation never resumes a continuation, so Pause looks broken too.
- **Confirm:** the diagnostics log records `request.start id=<salted>` / `request.end` pairs. The stall watchdog (F02)
  reports an unmatched start older than 20 s.
- **Fix (F03):** `withTimeout` plus `withTaskCancellationHandler` around every PhotoKit request. On timeout or cancel,
  call `PHImageManager.cancelImageRequest(_:)` / `PHAssetResourceManager.cancelDataRequest(_:)` (both verified in SDK
  headers), resume once with `nil` / `.timedOut`, and count the asset as "skipped: took too long" (never a match).

### H5. Memory
No `autoreleasepool` in the long loops. `UIImage`s from `PHCachingImageManager` and Vision buffers are drained only
when the main run loop turns. Whole-library arrays appear in `exactKeys()` (`LibraryStore.swift:252`),
`sequenceItems()` (`:374`), the candidate pair arrays (≤ 200k × 2) and `snapshots(ids:)` over all pair members
(`ScanEngine.swift:211`). With 7k items on a 12 GB 17 Pro this is not fatal, which matches "no jetsam entry". On a
3 GB iPhone SE (2nd gen) at 250k items it would be.
**Confirm:** Instruments *Allocations* + *VM Tracker*, `MXMemoryMetric.peakMemoryUsage`, and
`phys_footprint` / `os_proc_available_memory()` written to the diagnostics log every heartbeat.
**Fix (F03):** keyset-paged SQL for every phase (no whole-library arrays), 1–2 in-flight assets, 256-px thumbnails for
fingerprints and 384 px for Vision, `autoreleasepool` per asset, and a memory governor (§3).

### H6. Thermal pause
`.serious` pauses up to 600 s per checkpoint (`ResourceGovernor.swift:54-61`), and the checkpoint runs every 10 pairs,
so a warm phone can alternate pause and work for hours. The reason is shown, but only as a small caption.
**Confirm:** thermal state in each heartbeat log line. **Fix:** F05 makes the pause state the headline, and F03 shrinks
batches at `.fair`.

### H7. SQLite
A single actor with FULLMUTEX. Heavy queries (`nearHashPairs`, `momentPairs`) run off the main thread and are bounded
by bucket caps. Not a hang source today. They become costly at 250k, and scoping removes most of that.

## 2. Repro plan without a real library
1. F01 fixture: `FakePhotoLibrary.burstHeavy(count: 7_000, burstShare: 0.4, seed: 7)` **with thumbnails on** and a fake
   Vision cost (`FakeVisualCost.millisecondsPerRequest = 5`). Assert the pair count and the number of Vision calls. This
   reproduces H1 deterministically (count explosion) without timing.
2. `FakePhotoLibrary.stuckThumbnailIDs`: those requests never call back. The old engine waits forever (test with a 10 s
   XCTest timeout, expected to fail before F03 and pass after).
3. Re-render counter: a test-only `objectWillChange` counter over a 2,000-group scan (≤ 2 Hz × duration after F03).

## 3. On-device diagnostics to add (never leaves the device unless the user exports it)
| Piece | What | Feature |
|---|---|---|
| `DiagnosticsLog` | Rotating JSON-lines files in Application Support (2 × 512 KB), excluded from backup. Each event: time, phase, counters, thermal, `os_proc_available_memory`, `phys_footprint`, scene phase. **No identifiers** (salted asset-id hash only), no filenames, no locations. | F02 |
| Signposts | `OSSignposter(subsystem: "org.cleanslate.free", category: "scan")` intervals per phase and per asset request. | F02 |
| Main-thread watchdog | A background `DispatchSourceTimer` pings the main queue every 1 s. Any reply later than 250 ms is logged as `mainThreadBlocked(ms, phase)`. | F02 |
| Stall detector | Engine heartbeat per asset. No heartbeat for 20 s gives the event `stalled(phase, pendingRequests)`. The stuck request is cancelled (F03) and the UI shows "taking longer than usual" (F05). | F02/F03/F05 |
| MetricKit | `MXMetricManager.shared.add(_:)` (deprecated in the 27 SDK but available on the iOS 26 target). Persist `MXHangDiagnostic` / `MXCPUExceptionDiagnostic` / `MXMemoryMetric` summaries (JSON, local) into the log. | F02 |
| Memory pressure | `UIApplication.didReceiveMemoryWarningNotification` plus `DispatchSource.makeMemoryPressureSource` give `ResourceGovernor.memoryPressure = .warning/.critical`. Response: pause, drop caches, width 1, halve the batch. | F03 |
| Resume-after-kill | Already checkpointed per phase. Add `scan.inProgress` meta with scope and phase. On launch, if it is present and the app was not cleanly stopped, log `unexpectedTermination(lastPhase, lastHeartbeat)`. That is our own jetsam/watchdog detector. | F02/F03 |
| Export | Settings → "Diagnostics" → view a summary, **Share file** (ShareLink, user-initiated), **Delete**. | F02 |

## 4. Low-end implications (owner constraint)
The hang was seen on the fastest current iPhone. On the real target user's phone (iPhone SE 2nd gen at 3 GB, iPhone 11
or SE 3rd gen at 4 GB; iOS 26's floor is the A13) every H1 phase is roughly 3–5× slower (UNVERIFIED; measure in the
F03 device gate). H5 moves from "slow" to "jetsam kill", with whole-library arrays plus 512-px thumbnails plus uncached
Vision. So the fix is not "faster" but **bounded**: one asset in flight, 128-px fingerprints, paged SQL, flat
footprint (≤ 120 MB on tier L, ≤ 160 MB on tier M; see `FEATURE_ROADMAP.md`), a scope-first default of Recent 100, and
a progress UI that is never frozen (F05: stage, counts, found so far, heartbeat, stall message with Skip, and
Pause/Stop within 2 s).

## 5. Verdict
Fix H1 + H2 + H3 + H4 together in F03, behind the F01 harness and the F02 instrumentation. Scoped scanning (F04) is the
structural fix for H1. It does not replace the engine bounds, because "Everything" must still work on a 3 GB phone.
**Do not** ship another full-library scan to anyone until F03 passes its device gate (§ F03 "Human gates").
