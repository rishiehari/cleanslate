# F03: Scan stability and bounded memory (the hang fix)

## Goal and story
*As someone with an older, nearly full iPhone, the scan never freezes my phone or the app. It uses little memory, pauses
politely when the phone is warm or short of memory, keeps going if I leave the app, and picks up where it stopped.*
Fixes `HANG_RCA.md` H1–H6. Engine and view-model only. The visible progress UI is F05. Scopes are F04, but F03 already
takes a `limit` so the work is bounded.

## Trust / privacy / safety
- **No change to what can be deleted.** `SafetyPolicy`, the tray, the coordinator, `deleteAssets` and the
  policy-separation script are untouched. Commit-time snapshots still use `inspectAlbums: true`
  (`PhotoDeletionCoordinator.swift:58, 89, 145`), so the change below to scan-time album lookups cannot weaken album
  protection.
- Fail-closed: a timed-out digest = "couldn't check" (never a match). A timed-out thumbnail = "unavailable", same as
  iCloud-only today.
- No new network. `isNetworkAccessAllowed` stays false everywhere except `DigestFetcher`'s opt-in path.

## Device tier (see the budgets in `FEATURE_ROADMAP.md`)
- **Strictly one asset in flight** in this version on every tier (owner rule 4). `ResourceGovernor` may still return
  width 2, but the engine clamps to `ScanLimits.maxInFlight = 1`. Raising it is a later, measured change.
- Thumbnails: fingerprint **128 px** (`featureVersion` → 2), Vision 256/320/384 px by tier.
- Per-asset `autoreleasepool` around every synchronous image step. No `UIImage` outlives its asset's iteration.
- **No whole-library arrays.** Every phase pages from SQLite with a keyset cursor (≤ 500 rows per page). Caps:
  candidate pairs L 20k / M 40k / H 100k per pass; Vision pairs `min(30_000, 3 × scopeCount)`; the rest is reported as
  "left for next scan".
- Memory governor: `.warning` → drop caches, batch ÷ 4, width 1. `.critical`, or `os_proc_available_memory() < 100 MB`
  → pause up to 60 s, then stop with progress saved. Footprint above 1.2 × tier budget → drop caches + diagnostics event.
- Budget: peak footprint ≤ tier budget for scope 100 and scope 10,000 (fake, thumbnails ON), with growth ≤ 15 MB between
  them. Measured by `MemoryBudgetTests` (F01) on the default simulator and SE-test; the device check is a 🧑 gate.

## Files and changes
| Path | Change |
|---|---|
| `App/Services/PhotoKitLibraryClient.swift` | Timeouts + cancellation for `thumbnail` (10 s), `digest` (20 s **inactivity**, reset per data chunk), `verifiedSize` (10 s): `withTaskCancellationHandler` + a timer task that calls `imageManager.cancelImageRequest(id)` / `PHAssetResourceManager.default().cancelDataRequest(id)` and resumes the `OneShot` once. `inventoryPage`: wrap the loop in `autoreleasepool`. Add `albumMemberIDs(among:)` (per-asset `fetchAssetCollectionsContaining`, yield every 50). Keep `userAlbumAssetIDs()` for now but stop calling it from the scan. |
| `App/Services/PhotoLibraryClient.swift` | Add `func albumMemberIDs(among ids: [String]) async -> Set<String>`. Add `LibraryResourceError.timedOut`. |
| `App/Debug/FakePhotoLibrary.swift` | Implement `albumMemberIDs(among:)`. Stuck thumbnails honor the new client-side timeout via the shared helper (below). |
| `App/Services/Deadline.swift` (new) | `func withDeadline<T: Sendable>(_ seconds: Double, onExpire: @Sendable @escaping () -> Void, _ body: @escaping (OneShotResume<T>) -> Void) async -> T?`: generic one-shot continuation + timer + cancellation. Used by the client and the fake. |
| `App/Services/ScanLimits.swift` (new) | `struct ScanLimits { maxInFlight, inventoryPage = 100, featurePage = 100, fingerprintSide = 128, visionSide, candidatePairCap, visionPairCap(scopeCount:), momentBucketCap = 30 }`, built from `DeviceTier`. |
| `App/Services/ScanEngine.swift` | See "Engine changes". |
| `App/Store/LibraryStore.swift` | Paged queries: `exactKeyPage(afterRowID:limit:)`, `sequencePage(afterTime:afterID:limit:)`, `burstPage(afterBurstID:limit:)`; `momentPairs` bucket cap passed in (30); `nearHashPairs` returns at most `maximumPairs` (unchanged) with the caller's tier cap. **No schema change.** |
| `Core/Sources/CleanSlateCore/SequenceGrouping.swift` | Add `struct Streamer` (feed time-ordered pages, emit closed runs; bursts fed per burst id). `groups(_:)` is reimplemented on top of it so results stay identical. |
| `Core/Sources/CleanSlateCore/ExactCandidates.swift` | Add a streaming builder `ExactBucketBuilder` (`add(_ keys:)`, `finish()`). Same output as `buckets(_:)`, verified by a property test. Memory note: it keeps one small key per asset in scope (~60 B); for "Everything" on tier L at 250k that is ~15 MB, within budget. |
| `App/Services/ResourceGovernor.swift` | `Inputs.memoryPressure: @Sendable () -> MemoryPressure` (`.normal/.warning/.critical`), a `batchSize` published property, `dropCachesRequested` callback. |
| `App/Services/MemoryPressureMonitor.swift` (new) | `DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))` + `UIApplication.didReceiveMemoryWarningNotification` → latest level (decays to `.normal` after 30 s without events). |
| `App/Services/ScanHeartbeat.swift` (new) | `@MainActor final class ScanHeartbeat { func beat(); var secondsSinceBeat: Int; func startWatching(every: Duration, stallAfter: Int, onStall: @MainActor (Int) -> Void) }`. |
| `App/Services/CleaningViewModel.swift` | Coalesced reporting; incremental group/standalone bookkeeping; heartbeat; `skipCurrentStage()`; background hooks; `interruptedScan`. |
| `App/Services/BackgroundScanning.swift` + `App/CleanSlateApp.swift` | Call `BackgroundScanning.register()` in `CleanSlateApp.init` (before launch completes), set `BackgroundScanning.model`; `requestContinuedProcessing()` when a scan of > 500 items starts. |

### Engine changes (`ScanEngine.swift`)
1. `run(limit: Int?)`: `limit == nil` means everything. F04 replaces this with `ScanScope`.
2. **Fingerprints**: one asset at a time. `guard let image = await library.thumbnail(id, target: limits.fingerprintSide)`,
   then `let hash = await Task.detached(priority: .utility) { autoreleasepool { VisualFeatures.differenceHash(image) } }.value`.
   No `withTaskGroup` of `@MainActor` children. Beat the heartbeat per asset. Commit features every `governor.batchSize` (default 100).
3. **Candidates**: tier caps; build `Set`/`union`/`filter`/`rank` inside one `Task.detached` (pure data in, pairs out).
4. **Exact**: enqueue exact-bucket members plus **only** near pairs with Hamming ≤ 2 and equal width × height (likely
   re-saved copies). Order stays smallest bucket first. Cap = `min(4_000, scopeCount)`. Governor checkpoint every asset.
5. **Album marks**: `albumMemberIDs(among:)` over members of found groups and standalone items only.
6. **Review sets**: `SequenceGrouping.Streamer` over `sequencePage`. Quality per photo is computed **once**, cached in
   `[String: QualitySignals]` (LRU 2,000), and runs Vision at `visionSide`.
7. **Similar pairs**: `VisualPrint` LRU cache (64 entries) + quality cache shared with step 6. Per-request Vision
   deadline 10 s (`withDeadline`; the result is abandoned on expiry and counted as a Vision failure). Skip claimed
   pairs **before** loading thumbnails (already true) and before any Vision call.
8. Every phase checks `skipRequested` (set by `skipCurrentStage()`). It ends the phase, records
   `statistics.stagesSkipped += [phase]`, and moves on. Skipping never marks anything as matched.
9. Signposts and diagnostics hooks from F02 stay. Each timeout logs `requestTimedOut`.

### View-model changes
- `ScanProgressSnapshot` (struct: phase, done, total, foundGroups, foundBytesVerified, pauseReason, isStalled,
  startedAt) is published at **≤ 2 Hz** from a 0.5 s timer task. The engine writes to a non-published buffer.
  `statistics` publishes only at phase ends.
- `scanFound` appends to `pendingGroups`, flushed with the snapshot tick. Flushing updates the membership index
  incrementally (`GroupMembershipIndex.insert(groupID:members:)`, new Core API + tests). It also updates an
  `exactMemberIDs: Set<String>` incrementally, so `recomputeStandalone` runs only when standalone items or exact
  membership change. Remove the `didSet` side effects; call explicit `didChangeGroups(added:removed:)` instead.
- `scenePhase == .background` → flush diagnostics. The checkpoint is already per batch.

## Data model
No migration. Meta keys added: `scan.inProgress` (F02), `scan.featureVersion` is implicit (`featureVersion = 2`
invalidates v1 fingerprints through the existing `feature_version` column).

## Sub-tasks (one commit each, in order)
1. `Deadline.swift` + client timeouts/cancellation + `LibraryResourceError.timedOut`; flip `HangReproTests.stuck…` to a plain assert.
2. `ScanLimits` + `DeviceTier` wiring; strictly one in flight; 128-px fingerprints; `featureVersion = 2`.
3. Core `ExactBucketBuilder` + `SequenceGrouping.Streamer` + property tests (streaming == batch on 500 random libraries).
4. Paged store queries; engine uses them; candidate and moment caps; detached pair building.
5. Exact-enqueue narrowing; targeted album lookup.
6. Vision caches + per-request deadline.
7. `MemoryPressureMonitor` + governor memory input + batch size + drop caches.
8. `ScanHeartbeat` + stall detection (event + `isStalled`) + `skipCurrentStage()`.
9. View-model coalescing + incremental bookkeeping (+ `GroupMembershipIndex.insert` in Core).
10. Background registration + continued processing + scene-phase hooks.
11. Flip `HangReproTests` (pair/Vision bound) and `MemoryBudgetTests` to hard asserts; record numbers.

## Acceptance criteria
- `HangReproTests` pass without `XCTExpectFailure`: a stuck thumbnail costs ≤ 10 s and Cancel finishes within 2 s;
  7,000 burst-heavy assets give Vision calls ≤ 4 × (photos in review sets + 2 × pairs compared) with every print computed once per asset.
- `fake.maxThumbnailsInFlight == 1` across a whole scan.
- `MemoryBudgetTests`: peak ≤ tier budget; growth from 100 to 10,000 ≤ 15 MB (default simulator and SE-test).
- Re-render test: during a 2,000-group fake scan, `objectWillChange` fires ≤ 2 × seconds + phase count + 5.
- Main-thread watchdog (F02) records **no** block > 250 ms during the 10,000-photo fake scan with thumbnails ON.
- All existing tests pass unchanged, especially `ExactMatchingTests`, `ScanEngineTests`, `ScaleTests` and every `SafetyPolicyTests` assertion.
- `scripts/check_policy_separation.sh` passes. `grep -rn "deleteAssets" App` gives 1.

## Test plan / validator checklist
- Timeouts: stuck thumbnail, stuck digest (fake `stuckDigestIDs`), stuck video size, Vision deadline (fake sleeps 15 s).
- Cancellation during each phase finishes within 2 s and saves progress; the next scan resumes (inventory offset, feature cursor).
- Memory pressure: injected `.warning` → batch shrinks and caches drop. `.critical` for 61 s → stops with the message "Paused to free memory. Your progress is saved."
- Thermal: existing tests plus "`.fair` → width 1".
- Skip: skipping "Comparing" still keeps the exact groups found; nothing gets marked.
- Corner: 0 photos, 1 photo, all iCloud-only, every thumbnail times out (the scan completes with an honest count), limited access, a library change mid-scan, token expired.
- Safety negatives: a timed-out digest never forms an exact group; an album member found in a group is still protected (fake `albumMemberIDs`); a favorite inside a burst is never pre-marked.
- Device (🧑): 17 Pro + an SE 2/3 or iPhone 11 on a **disposable or owner-approved read-only** library of ≥ 7,000 items. Capture the F02 diagnostics file, Instruments Hangs + Allocations, peak footprint versus budget, and time per phase.

## Privacy review
No new data leaves the device. Background continuation shows the system progress UI with the title "Looking for
copies", with no photo details.

## Rollback
Each sub-task is a commit. The riskiest are 4 and 9: revert them individually, since the paged queries keep the old
API alongside. Keep `featureVersion = 2` even on rollback (re-fingerprinting is harmless).

## Dependencies
F01 (harness, seam), F02 (events, watchdog). Blocks F04 and F05.

## Definition of done
All acceptance criteria are green in `make ci` + `make budget`, `/code-review high` findings are resolved, validator
PASS-TO-GATE, gatekeeper APPROVE, and the 🧑 device read-only scan is logged with the diagnostics file and Instruments
captures. **Stability gate:** no other feature starts until this device evidence exists.
