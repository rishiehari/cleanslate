# F01: Synthetic burst/overlap fixtures, 100-photo end-to-end test, low-memory harness

## Goal and story
*As the team, we can reproduce a burst-heavy library, a stuck PhotoKit callback and a low-RAM budget without ever
touching a real library, so every later feature is proven fast, flat in memory and correct before it ships.*
Test infrastructure only. Production behaviour is unchanged except for one pure refactor (a Vision seam).

## Trust / privacy / safety
- No real photos anywhere. Python fixtures are drawn from primitives (no people). Fake libraries are in memory.
- The E2E test exercises the full Review → Approve → Tray → Delete path on the fake, asserting U1/U4 and that every
  protected item survives. It is a safety regression net for F03–F10.

## Device tier
Introduces the measuring tools that every later feature uses: `FootprintSampler` (peak `phys_footprint`), the tier
budgets from `FEATURE_ROADMAP.md`, and a `make budget` target on the **SE-test** simulator (iPhone SE 3rd gen device
type; it already exists locally, and the target creates it if missing).

## Files
| Action | Path |
|---|---|
| modify | `fixtures/generate_synthetic_photos.py`: add `--bursts N` mode |
| modify | `fixtures/test_generator.py`: tests for the burst mode |
| modify | `scripts/seed_simulator.sh`: optional `--bursts` passthrough |
| create | `App/Services/VisualAnalyzing.swift`: protocol + `VisionVisualAnalyzer` (wraps `VisualFeatures`) |
| modify | `App/Services/ScanEngine.swift`: take `visual: VisualAnalyzing` in `init` (default `VisionVisualAnalyzer()`); replace the direct `VisualFeatures.printFeature/faceQuality/aesthetics/distance` calls. **No logic change.** |
| modify | `App/Debug/FakePhotoLibrary.swift`: `RenderSpec`, scenario builders, stuck thumbnails |
| create | `App/Debug/FakeVisualAnalyzer.swift` |
| create | `iOSTests/Support/FootprintSampler.swift` |
| create | `iOSTests/EndToEndRecent100Tests.swift` |
| create | `iOSTests/HangReproTests.swift` |
| create | `iOSTests/MemoryBudgetTests.swift` |
| modify | `Makefile`: `budget` target |

## Types
```swift
// App/Services/VisualAnalyzing.swift
protocol VisualAnalyzing: Sendable {
    func featurePrint(_ image: UIImage) async throws -> FeaturePrintObservation   // keep the existing return type
    func distance(_ a: FeaturePrintObservation, _ b: FeaturePrintObservation) throws -> Double
    func faceQuality(_ image: UIImage) async throws -> Double?
    func aesthetics(_ image: UIImage) async throws -> Double
}
struct VisionVisualAnalyzer: VisualAnalyzing { /* forwards to VisualFeatures.* */ }
```
`FeaturePrintObservation` cannot be built by a fake. Make the seam return an opaque `VisualPrint` instead:
`struct VisualPrint: Sendable { let distanceTo: @Sendable (VisualPrint) throws -> Double }`. The real version wraps the
observation; the fake carries a `look` vector. Use `VisualPrint` in the protocol and drop
`distance(_:_:)`, using `a.distanceTo(b)`.

```swift
// App/Debug/FakeVisualAnalyzer.swift (DEBUG)
final class FakeVisualAnalyzer: VisualAnalyzing, @unchecked Sendable {   // counters behind OSAllocatedUnfairLock
    var calls: Int { get }              // every request counted
    var failAll = false                 // simulator-like Vision failure
}
```
The fake derives distance from the asset's `RenderSpec` (same base → 0.1, shifted ≤ 2 → 0.2, different → 0.9).

```swift
// FakePhotoLibrary additions (DEBUG)
struct RenderSpec: Hashable, Sendable { var base: Int; var shiftX: Int = 0; var exposure: Double = 1; var extraSubject = false }
static func burstHeavy(count: Int, burstShare: Double, burstLength: Int, seed: UInt64) -> FakePhotoLibrary
static func recent100Scenario() -> (library: FakePhotoLibrary, expectations: Recent100Expectations)
var stuckThumbnailIDs: Set<String>  // thumbnail() suspends until releaseStuckThumbnails(); ignores cancellation (like PhotoKit)
func releaseStuckThumbnails()
var thumbnailsInFlight: Int { get }; var maxThumbnailsInFlight: Int { get }   // backpressure assertions
```
`renderScene(look:)` gains a `RenderSpec` overload: the hills shift by `shiftX * 6` px, brightness scales by
`exposure`, and `extraSubject` adds a circle. Assets created by `add(...)` without a spec keep today's look, so existing
tests are unchanged.

`Recent100Expectations`: ids of 5 exact pairs, 3 bursts × 6 (same `burst`), 2 overlap runs × 5 (1 s apart, shift 1–4),
4 protected items (favorite copy, album member, edited, shared), 10 screenshots, and the remaining unique photos.
Total 100, all with `capturedAt` within the last 30 days.

```swift
// iOSTests/Support/FootprintSampler.swift
final class FootprintSampler { init(interval: Duration = .milliseconds(100)); func start(); func stop() -> (peakMB: Double, startMB: Double) }
// uses task_info(mach_task_self_, TASK_VM_INFO, ...) and reads phys_footprint
```

## Python `--bursts N`
For each of N bursts, write 8 JPEG frames from one base scene: a 0–14 px pan, ±6% exposure, an expression change on
frame 5, and the subject missing on frame 7. Set EXIF `DateTimeOriginal` one second apart (Pillow `Image.Exif`, tag
36867). Add manifest rows with labels `burst_redundant` / `unique_expression` / `unique_subject`. Note in the script
header: simulator imports cannot create real `burstIdentifier`s, so these test the **time-window** path. True bursts
exist only on the fake.

## Sub-tasks (one commit each)
1. `VisualAnalyzing` + `VisualPrint` seam; `ScanEngine` uses it. All existing tests stay green (pure refactor).
2. `RenderSpec`, `FakeVisualAnalyzer`, the `burstHeavy` and `recent100Scenario` builders.
3. Stuck thumbnails + in-flight counters in the fake.
4. `FootprintSampler` + `MemoryBudgetTests` (thumbnails ON, scopes 100 and 10,000; uses the tier budget for the running device).
5. `HangReproTests`: (a) a 7,000-photo burst-heavy library gives `visual.calls` above the bound; (b) a stuck thumbnail
   hangs the scan (Cancel fails to finish within 5 s). Both are wrapped in `XCTExpectFailure("fixed by F03")`, documenting
   the bug and flipping to plain asserts in F03.
6. `EndToEndRecent100Tests` (full scan for now; F04 switches it to the Recent 100 scope).
7. Python `--bursts` + tests; `make budget` (`xcrun simctl list | grep SE-test || xcrun simctl create SE-test com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation`, then `-only-testing:CleanSlateTests/MemoryBudgetTests`).

## Acceptance criteria
- `make ci` green. No existing test edited (except `ScanEngine` construction, if a default parameter can't keep it compiling).
- E2E: 5 exact groups pre-marked; bursts and overlap runs appear as similar groups with **nothing pre-marked**;
  approving every exact group → tray → `deleteTray()` → fake `deleteCalls.count == 1`. The 4 protected items still
  exist. The receipt has `verifiedRemoved == 5`.
- Repro tests fail as expected (recorded via XCTExpectFailure) and log the measured numbers.
- `make fixtures-test` covers burst mode (frame count, 1 s EXIF spacing, labels).

## Test plan / validator checklist
- Corner cases: empty library; 1 photo; a 100-photo library where all photos are protected; all thumbnails unavailable; `failAll` Vision.
- Determinism: the same seed gives identical ids, specs and groups across two runs.
- Negative: `extraSubject` frames are never in a pre-marked state; a favorite inside a burst is never marked.
- Budget test runs on SE-test and on the default simulator; both print `peakMB`.

## Privacy review
Test code and DEBUG-only fakes. Nothing ships in Release (`#if DEBUG` on all `App/Debug` files; verify with a Release build).

## Rollback
Revert commits 2–7 freely. Commit 1 (the seam) is a behaviour-neutral refactor; if reverted, revert F01 as a whole.

## Dependencies
None. Blocks F03–F10 (they extend these tests).

## Definition of done
All sub-tasks committed, `make ci` + `make budget` run with counts logged in `VALIDATION_LOG.md`, validator
PASS-TO-GATE, gatekeeper APPROVE.
