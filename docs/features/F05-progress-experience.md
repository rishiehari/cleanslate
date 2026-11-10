# F05: Progress you can trust (never a frozen screen)

## Goal and story
*While CleanSlate is working, I always see what it is doing, how far along it is, and what it has already found. I can
pause or stop at any moment. If something takes unusually long it tells me, lets me skip that step, and says it is safe
to leave.*

## Trust / privacy / safety
- Honest numbers only: counts are real units of the current stage, an ETA appears only when it is stable (below),
  and "found so far" uses verified bytes for exact copies and a count (no bytes) for similar shots (U10).
- **Skip** ends the current stage only. It never marks, approves or deletes anything.
- Review while scanning (U12): groups can be opened during the scan. A group found earlier is never mutated by a later
  stage except through the existing recheck path.

## Device tier
UI updates come from F03's 2 Hz `ScanProgressSnapshot`. The progress view must not add per-asset work: no thumbnails
in the progress card, and the "found so far" tally is computed incrementally in the view model. Reduce Motion: no
animated heartbeat, just a text change.

## Stages (user words → engine phases)
| Stage | Engine phases | Units shown |
|---|---|---|
| **Reading** | inventory, thumbnails | "Reading 84 of 100 photos" |
| **Comparing** | candidates, fullResources, vision | "Comparing 212 of 1,040 possible matches" |
| **Grouping** | sizing, review sets, final sort | "Grouping 12 of 40" |
Stage progress is determinate per stage. The overall bar = stage index / 3 + stage fraction / 3 (no fake smoothing).

## Files
| Action | Path |
|---|---|
| create | `App/Models/ScanStage.swift`: `enum ScanStage { case reading, comparing, grouping }` + mapping from `ScanPhase` |
| create | `App/Services/EtaEstimator.swift`: pure, testable |
| create | `App/Views/ScanProgressCard.swift`: replaces `ScanStatusCard` while scanning |
| modify | `App/Views/ScanStatusCard.swift`: idle/finished states only |
| modify | `App/Services/CleaningViewModel.swift`: `ScanProgressSnapshot` gains `stage`, `stageDone`, `stageTotal`, `foundExactGroups`, `foundSimilarGroups`, `foundVerifiedBytes`, `lastBeatAt`, `isStalled`, `eta: Duration?`; `cancelScan()` (stop and keep results) vs `pause()` (same engine call, different copy) |
| modify | `App/Services/ScanEngine.swift`: report `(stage, done, total)` through the reporter for every unit (buffered, F03) |
| modify | `App/Views/DashboardView.swift`: the card is pinned at the top while scanning; categories update live |
| create | `UITests/ScanProgressUITests.swift`, `iOSTests/EtaEstimatorTests.swift` |
| modify | `App/Debug/FakePhotoLibrary.swift`: `thumbnailDelay: Duration` (slow mode for UI tests), `stuckThumbnailIDs` already exists |

## Types
```swift
struct EtaEstimator {
    init(minimumSamples: Int = 20, minimumElapsed: Duration = .seconds(10))
    mutating func record(done: Int, total: Int, at: ContinuousClock.Instant)
    var estimate: Duration? { get }   // nil until stable: ≥ 20 units and ≥ 10 s elapsed in this stage, and the
                                      // last 3 estimates within ±25% of each other; rounded up to whole minutes; nil if > 3 h
}
```

## UI spec: `ScanProgressCard` (`scan.progress`)
- Line 1: stage name, `.groupTitle`: "Reading your 100 most recent photos" / "Comparing" / "Grouping".
- `ProgressView(value:)` (`scan.progress.bar`), with accessibility value "42 percent".
- Line 2 (`scan.progress.count`): "84 of 100" plus " · about 2 min left" when `eta != nil`. Without an ETA: "Elapsed 0:42".
- **Found so far** (`scan.progress.found`): "Found 3 sets of copies (12.4 MB) and 5 similar sets". `.numericText()` transition. Tappable: jumps to the category list (review while scanning).
- **Heartbeat** (`scan.progress.heartbeat`): a small `symbolEffect(.pulse)` on `waveform.path.ecg`, only when the
  last beat was < 3 s ago. Static under Reduce Motion. VoiceOver: hidden (the counts carry the information).
- **Stalled** (`isStalled`, no beat for 20 s; F03 sets it): replace line 2 with "This is taking longer than usual.
  It's safe to leave; CleanSlate picks up where it stopped." Buttons: **Skip this step** (`scan.progress.skip`),
  **Keep waiting**. Posts a VoiceOver announcement once.
- **Paused** by the governor: the headline becomes the reason ("Paused: your iPhone is warm", "Paused to free
  memory"), with **Resume** (`scan.progress.resume`), which retries the checkpoint now.
- Buttons always visible: **Pause** (`scan.progress.pause`, `.glass`) and **Stop** (`scan.progress.stop`, plain).
  Stop shows an inline confirmation: "Stop checking? You keep everything found so far." Pause keeps the scope for
  resume. Stop clears `scan.inProgress`.
- After the app relaunches with `interruptedScan` set (F03): the card shows "Your last check stopped early" with
  **Continue** and **Not now** (`scan.resume.continue`).
- Leaving the app during a large scope: on the first background with `scope.isLarge`, the continued-processing system
  UI appears (F03). In-app, a one-time line: "You can use other apps. CleanSlate keeps going for a while."
- Layout: the card is not glass (content). The buttons are glass inside one `GlassEffectContainer`. AX5: buttons stack
  vertically, and the counts wrap.

## Sub-tasks
1. `ScanStage` mapping + engine unit reporting + snapshot fields + tests (stage totals are correct per phase on the fake).
2. `EtaEstimator` + tests (nil early; stable; jittery input stays nil; > 3 h → nil).
3. `ScanProgressCard` (normal / paused / stalled / interrupted states) with previews for each.
4. Skip / Stop / Pause / Resume wiring.
5. Found-so-far tally (incremental) + tap-through to the categories while scanning.
6. UI tests + accessibility audit + Reduce Motion check.

## Acceptance criteria (UI tests, fake library with `thumbnailDelay = 30 ms`, Recent 100)
- `scan.progress.count`'s value changes at least 3 times within 5 s, and `scan.progress.bar`'s value increases monotonically.
- `scan.progress.found` shows ≥ 1 set before the scan ends; tapping it opens the Exact category while `scan.progress` still exists.
- Stop → within 2 s `scan.progress` disappears, the found groups remain, and `debug.probe` shows `deleteCalls=0`.
- Pause → Continue resumes and finishes without re-reading (fake `thumbnailCalls` does not double).
- With `stuckThumbnailIDs = [one id]` and a 3 s stall threshold (test launch argument `-stallSeconds 3`), the stall text appears, and **Skip this step** moves to the next stage.
- `performAccessibilityAudit()` passes in the scanning, paused and stalled states.

## Test plan / validator checklist
Unit: stage mapping for every `ScanPhase`; the found tally equals the final group counts; ETA rules. UI: as above + AX5
screenshots + dark mode. Negatives: Skip during Comparing never adds tray entries; tapping Stop twice is idempotent;
scanning with 0 photos shows the empty state, not a stuck bar. Corner: governor `.serious` during Reading shows the
paused state, then resumes; a relaunch mid-scan shows the interrupted state once.

## Privacy review
No new data. Announcements contain counts only.

## Rollback
Re-enable the old `ScanStatusCard` scanning branch (kept for one release behind a flag `progress.v2`, default on).

## Dependencies
F03 (snapshot, heartbeat, skip), F04 (scope names). Feeds F07 (scan events).

## Definition of done
UI tests green, screenshots (light/dark/AX3, stalled and paused states) in `docs/screens/F05/`, feedback audit row for
"scan found first group" and "scan done" (≥ 2 channels: text + haptic or VoiceOver), validator + gatekeeper approved.
