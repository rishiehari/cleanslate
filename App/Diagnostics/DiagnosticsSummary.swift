import Foundation

/// The five headline numbers for Settings → Diagnostics, derived from the log's records (oldest first).
/// Pure value type so the mapping is unit-testable.
struct DiagnosticsSummary: Equatable {
    var lastScanOutcome: DiagOutcome?
    var lastScanSeconds: Int?
    var stallsLast7Days = 0
    var slowMoments = 0
    var memoryWarnings = 0
    var lastUnexpectedStop: Date?

    init(records: [DiagnosticRecord], now: Date = Date()) {
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3_600)
        for record in records {          // recent() is oldest-first: later matches win
            switch record.event {
            case .scanEnded(let outcome, let seconds, _):
                lastScanOutcome = outcome; lastScanSeconds = seconds
            case .stalled where record.t >= weekAgo:
                stallsLast7Days += 1
            case .mainThreadBlocked:
                slowMoments += 1
            case .memoryWarning:
                memoryWarnings += 1
            case .appLaunch(_, _, _, let clean, _) where !clean:
                lastUnexpectedStop = record.t
            default:
                break
            }
        }
    }
}

extension DiagnosticEvent {
    /// One plain-language line per event for "Show details" on the Diagnostics screen.
    /// Counts, durations and closed-enum words only — never ids, filenames or photo dates.
    var summaryLine: String {
        switch self {
        case .appLaunch(_, _, _, let clean, let lastPhase):
            clean ? "App opened normally"
                  : "App reopened after stopping unexpectedly\(lastPhase.map { " during \($0.plainName)" } ?? "")"
        case .scenePhase(let state):
            switch state {
            case .active: "App came to the front"
            case .inactive: "App lost focus"
            case .background: "App went to the background"
            }
        case .scanStarted(_, let items):
            "Scan started across \(items.formatted()) photos"
        case .phaseEntered(let phase, let units):
            units > 0 ? "Started \(phase.plainName) (\(units.formatted()) items)" : "Started \(phase.plainName)"
        case .phaseEnded(let phase, let millis, _, _):
            "Finished \(phase.plainName) in \(Self.duration(millis))"
        case .progress(let phase, let done, let total):
            "\(phase.plainName.capitalizingFirst) — \(done.formatted()) of \(total.formatted())"
        case .thumbnailStats(let tried, let unavailable, let percent):
            "Thumbnails: \(percent)% not stored on this iPhone (\(unavailable.formatted()) of \(tried.formatted()) tried)"
        case .heartbeat(let phase, let done, let total, let footprint, let available, _, _, let inFlight, _, _):
            "\(phase.plainName.capitalizingFirst) — \(done.formatted()) of \(total.formatted()), memory \(footprint) MB"
                + " (\(available.formatted()) MB free), \(inFlight) in flight"
        case .stalled(let phase, let seconds, let pending):
            "No progress while \(phase.plainName) for \(seconds) s — \(pending) request(s) pending"
        case .requestTimedOut(let kind, _, let seconds):
            "\(kind.plainName) request took over \(seconds) s for one photo"
        case .mainThreadBlocked(let ms, let phase):
            "Screen froze for \(Self.milliseconds(ms))\(phase.map { " while \($0.plainName)" } ?? "")"
        case .governor(let decision, let reason):
            "\(decision.plainName) — iPhone is \(reason.plainName)"
        case .memoryWarning(let footprint):
            "iPhone reported low memory (using \(footprint) MB)"
        case .scanEnded(let outcome, let seconds, let groups):
            "Scan \(outcome.plainName) after \(Self.duration(seconds * 1_000)) — \(groups.formatted()) group(s) found"
        case .metricKit(.hang, let summary):
            "iOS reported a freeze: \(summary.count ?? 1) hang(s), \(Self.duration(summary.hangDurationMs ?? 0)) in total"
        case .metricKit(.cpuException, let summary):
            "iOS reported high CPU use: \(summary.count ?? 1) time(s), \(Self.duration(summary.cpuTimeMs ?? 0)) in total"
        case .metricKit(.metrics, _):
            "iOS delivered a metrics report"
        }
    }

    /// 900 → "1 s", 65_000 → "1 min 5 s".
    static func duration(_ millis: Int) -> String {
        let seconds = (millis + 500) / 1_000
        if seconds < 60 { return "\(seconds) s" }
        return "\(seconds / 60) min \(seconds % 60) s"
    }

    static func milliseconds(_ ms: Int) -> String { ms < 1_000 ? "\(ms) ms" : duration(ms) }
}

extension DiagPhase {
    /// Lower-case on purpose: these read mid-sentence ("while comparing similar shots").
    var plainName: String {
        switch self {
        case .idle: "idle"
        case .inventory: "looking through your library"
        case .thumbnails: "checking photos"
        case .candidates: "finding copies"
        case .fullResources: "checking original files"
        case .vision: "comparing similar shots"
        case .sizing: "measuring items"
        case .finished: "wrapping up"
        case .cancelled: "stopping"
        }
    }
}

extension DiagOutcome {
    var plainName: String {
        switch self {
        case .finished: "finished"
        case .paused: "paused"
        case .stopped: "stopped"
        }
    }
}

extension DiagGovernorDecision {
    var plainName: String {
        switch self {
        case .pause: "Paused"
        case .shrink: "Slowed down"
        case .stop: "Stopped"
        }
    }
}

extension DiagGovernorReason {
    var plainName: String {
        switch self {
        case .thermal: "warm"
        case .lowMemory: "low on memory"
        case .lowPower: "in Low Power Mode"
        case .memoryWarning: "low on memory after a warning"
        }
    }
}

extension DiagRequestKind {
    var plainName: String {
        switch self {
        case .thumbnail: "Thumbnail"
        case .digest: "Original-file check"
        case .videoSize: "Video size"
        case .vision: "Similar-photo comparison"
        }
    }
}

private extension String {
    var capitalizingFirst: String { prefix(1).uppercased() + dropFirst() }
}
