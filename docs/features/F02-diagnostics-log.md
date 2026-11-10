# F02: On-device diagnostics log (local only, user-exported only)

## Goal and story
*As the owner or a tester, when a scan stalls I can open Settings → Diagnostics and see what the app was doing, and
choose to share a file that contains no photo information.*
*As the team, we can confirm or reject each `HANG_RCA.md` hypothesis on a real device.*

## Trust / privacy / safety
- Stored in `Application Support/Diagnostics/`, with `isExcludedFromBackup = true` and protection
  `completeUntilFirstUserAuthentication`. **Never transmitted.** Export happens only through a user tap on `ShareLink`.
- **Content allow-list** (enforced by type, not by convention): event name, timestamp, phase, integer counters,
  durations, thermal state, memory numbers, scene phase, app version/build, device tier (L/M/H). **Forbidden:**
  `localIdentifier`, filenames, dates of photos, locations, album names, free text from Vision. When one asset must be
  correlated across events, use `SaltedID` (SHA-256 of a per-install random salt + id, first 8 bytes). The salt is
  stored in the Keychain-less app container and wiped with the log.
- Diagnostics never influence deletion.

## Device tier
- Writes are buffered: at most 64 events in memory, flushed every 5 s or on background. Two files × 512 KB, rotating:
  **≤ 1 MB on disk, ≤ 100 KB RAM**.
- The heartbeat event (every 5 s during a scan) costs one syscall for `task_info` plus `os_proc_available_memory()`.
- The main-thread watchdog runs on a utility `DispatchSourceTimer` (1 s), so it costs essentially nothing.

## Files
| Action | Path |
|---|---|
| create | `App/Diagnostics/DiagnosticEvent.swift`: `enum DiagnosticEvent: Codable, Sendable` (closed set, see below) |
| create | `App/Diagnostics/DiagnosticsLog.swift`: `actor DiagnosticsLog` (rotation, flush, read, delete, export URL) |
| create | `App/Diagnostics/MainThreadWatchdog.swift` |
| create | `App/Diagnostics/MetricKitCollector.swift`: `final class MetricKitCollector: NSObject, MXMetricManagerSubscriber` |
| create | `App/Diagnostics/ScanSignposts.swift`: `OSSignposter(subsystem: "org.cleanslate.free", category: "scan")` |
| create | `App/Diagnostics/MemoryProbe.swift`: `static func footprintMB() -> Double` (TASK_VM_INFO `phys_footprint`), `availableMB()` |
| create | `App/Views/DiagnosticsView.swift` |
| modify | `App/Services/ScanEngine.swift`: phase signposts + `log.record(...)` at phase boundaries, every 25 items and every heartbeat |
| modify | `App/CleanSlateApp.swift`: create the shared `DiagnosticsLog`, start the watchdog and the MetricKit collector, log scene phase, run the unexpected-termination check |
| modify | `App/Views/DashboardView.swift`: menu item "Diagnostics" |
| modify | `App/Resources/PrivacyInfo.xcprivacy`: **only if** a required-reason API is newly used (file timestamps are not needed; verify) |
| create | `iOSTests/DiagnosticsLogTests.swift` |

## Types
```swift
enum DiagnosticEvent: Codable, Sendable {
    case appLaunch(version: String, build: String, tier: DeviceTier, previousRunEndedCleanly: Bool, lastPhase: String?)
    case scenePhase(String)                                    // "active" | "inactive" | "background"
    case scanStarted(scope: String, items: Int)                // scope kind only, e.g. "recent100"
    case phaseEntered(String, units: Int)
    case heartbeat(phase: String, done: Int, total: Int, footprintMB: Int, availableMB: Int, thermal: Int, inFlight: Int)
    case stalled(phase: String, secondsSinceProgress: Int, pendingRequests: Int)
    case requestTimedOut(kind: String, asset: SaltedID, seconds: Int)   // kind: thumbnail|digest|videoSize|vision
    case mainThreadBlocked(ms: Int, phase: String?)
    case governor(decision: String, reason: String)            // pause/shrink/stop + why
    case memoryWarning(level: String, footprintMB: Int)
    case scanEnded(outcome: String, seconds: Int, groupsFound: Int)
    case metricKit(kind: String, summary: [String: Int])        // hangDurationMs, peakMemoryMB, cpuTimeMs …
}
struct DiagnosticRecord: Codable, Sendable { let t: Date; let event: DiagnosticEvent }
enum DeviceTier: String, Codable, Sendable { case low, mid, high; static var current: DeviceTier }  // physicalMemory
struct SaltedID: Codable, Sendable, Hashable { let value: String }

actor DiagnosticsLog {
    static let shared: DiagnosticsLog
    init(directory: URL?, maxFileBytes: Int = 512 * 1024, now: @Sendable () -> Date = Date.init)
    func record(_ event: DiagnosticEvent)
    func flush() async
    func recent(limit: Int) -> [DiagnosticRecord]
    func exportFile() throws -> URL        // concatenates both files into a temp .jsonl, newest last
    func deleteAll() throws               // also rotates the salt
    nonisolated func salted(_ id: String) -> SaltedID
}
```
Unexpected-termination check: at scan start, write meta `scan.inProgress` = `{scope, phase}` (in `LibraryStore.meta`).
Clear it at a clean end, a pause or a stop. On launch, if it is present → `appLaunch(previousRunEndedCleanly: false,
lastPhase:)`. MetricKit: `MXMetricManager.shared.add(self)` (deprecated in the 27 SDK, available on 26; wrap in one
file so it can move to the iOS 27 Swift `MetricManager` later). In `didReceive(_ payloads: [MXDiagnosticPayload])`,
reduce each `hangDiagnostics` / `cpuExceptionDiagnostics` entry to numbers only (call stacks are **not** stored, because
they can contain symbol paths; that is acceptable since there are no user data, but it is noise).

## UI spec: `DiagnosticsView` (pushed from Settings menu → "Diagnostics")
- Header text: "A private record of how scans ran on this iPhone. It never leaves your phone unless you share it."
- Summary rows: Last scan (outcome, duration), Stalls in the last 7 days, Slow moments (main-thread blocks), Memory
  warnings, Last unexpected stop.
- "Show details": a `List` of the last 200 events in plain words (e.g. "Comparing: paused, iPhone is warm").
- Buttons: `ShareLink("Share diagnostics file", item: url)` with a preview line "Contains timings and counts only.
  No photos, names, dates or places." and "Delete diagnostics" (confirmation alert).
- `ContentStateView` empty state: "Nothing recorded yet".
- Identifiers: `diagnostics.screen`, `diagnostics.share`, `diagnostics.delete`, `diagnostics.summary`.
- Dynamic Type to AX5 (rows stack), VoiceOver reads each summary row as one element. No glass on content.

## Sub-tasks
1. `DiagnosticEvent`, `DiagnosticsLog` (rotation, flush, delete, export) + tests.
2. `MemoryProbe`, `DeviceTier` + tests (tier thresholds via an injectable `physicalMemory`).
3. `ScanSignposts` + engine hooks (phase boundaries, every 25 items, heartbeat every 5 s from a timer task in `CleaningViewModel.runScan`).
4. `MainThreadWatchdog` (utility queue timer posts to main; reply latency > 250 ms gives `mainThreadBlocked`) + test with an injected clock.
5. Unexpected-termination detection + `scenePhase` logging.
6. `MetricKitCollector` (numbers only).
7. `DiagnosticsView` + menu entry + UI test + accessibility audit.

## Acceptance criteria
- A leak test (like the Label-mode test): after a fake scan of `recent100Scenario`, the exported file contains **none**
  of the asset ids, filenames or capture dates (search the bytes for each). Every JSON key belongs to the allow-list.
- Rotation: writing 3 MB of events leaves ≤ 2 files and ≤ 1 MB.
- Delete removes the files and rotates the salt (`salted("x")` differs before and after).
- A scan killed mid-phase (simulated: write `scan.inProgress`, recreate the model) logs `previousRunEndedCleanly: false`.
- `grep -rn "URLSession\|isNetworkAccessAllowed = true" App` is unchanged.

## Test plan
Unit: the above + concurrency (1,000 concurrent `record` calls lose nothing before rotation). UI: open Diagnostics,
Share button exists, Delete → empty state; `performAccessibilityAudit()`. Negative: unwritable directory → the log
silently disables itself, and the scan still runs. Corner: clock going backwards, disk full (write fails, no crash).

## Privacy review
Local file, user-initiated share only, allow-listed fields, salted ids, no stacks. App Privacy stays "Data Not
Collected" because nothing is collected by the developer. 🧑 The owner confirms that wording.

## Rollback
The feature is additive. Remove the menu entry and the `record` calls (they are no-ops if the log is nil).

## Dependencies
F01 (fixtures for the leak test). Needed by F03 (stall detector, timeouts write events) and F05 (stall message reads
the same heartbeat).

## Definition of done
Merged, tests green, validator + gatekeeper approved. 🧑 The owner runs one scan on the 17 Pro with the **old engine
plus F02** and shares the file, which confirms or rejects H1–H4 before F03 begins (recommended, not blocking).
