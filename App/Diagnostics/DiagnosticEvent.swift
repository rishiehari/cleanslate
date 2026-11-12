import Foundation

// The diagnostics log is allow-listed BY TYPE: every field below is a number, a flag or a value of a closed enum.
// There is deliberately no free-text String payload, so a photo identifier, filename, date, place or Vision text cannot
// be logged by accident. Where one asset must be correlated across events, use `SaltedID`.

/// A scan stage, as a closed set. Mirrors `ScanPhase` without carrying its user-facing text.
enum DiagPhase: String, Codable, Sendable, CaseIterable {
    case idle, inventory, thumbnails, candidates, fullResources, vision, sizing, finished, cancelled
}

enum DiagScope: String, Codable, Sendable { case all, bounded }
enum DiagScene: String, Codable, Sendable { case active, inactive, background }
enum DiagRequestKind: String, Codable, Sendable { case thumbnail, digest, videoSize, vision }
enum DiagGovernorDecision: String, Codable, Sendable { case pause, shrink, stop }
enum DiagGovernorReason: String, Codable, Sendable { case thermal, lowMemory, lowPower, memoryWarning }
enum DiagOutcome: String, Codable, Sendable { case finished, paused, stopped }
enum DiagMetricKind: String, Codable, Sendable { case metrics, hang, cpuException }

/// SHA-256(per-install random salt + id), first 8 bytes as hex. Never the id itself.
struct SaltedID: Codable, Sendable, Hashable { let value: String }

/// Numbers only. MetricKit call stacks are never stored.
struct MetricSummary: Codable, Sendable, Equatable {
    var count: Int?
    var hangDurationMs: Int?
    var peakMemoryMB: Int?
    var cpuTimeMs: Int?
}

enum DiagnosticEvent: Codable, Sendable, Equatable {
    case appLaunch(version: String, build: String, tier: DeviceTier, previousRunEndedCleanly: Bool, lastPhase: DiagPhase?)
    case scenePhase(state: DiagScene)
    case scanStarted(scope: DiagScope, items: Int)
    case phaseEntered(phase: DiagPhase, units: Int)
    case phaseEnded(phase: DiagPhase, millis: Int, done: Int, total: Int)
    /// Progress inside a stage, every 25 items.
    case progress(phase: DiagPhase, done: Int, total: Int)
    /// How many thumbnail requests found no local picture (PhotoKit 3303 "no resource found") out of those tried.
    case thumbnailStats(tried: Int, unavailable: Int, unavailablePercent: Int)
    case heartbeat(phase: DiagPhase, done: Int, total: Int, footprintMB: Int, availableMB: Int, thermal: Int, lowPower: Bool,
                   inFlight: Int, thumbsTried: Int, thumbsUnavailable: Int)
    case stalled(phase: DiagPhase, secondsSinceProgress: Int, pendingRequests: Int)
    case requestTimedOut(kind: DiagRequestKind, asset: SaltedID, seconds: Int)
    case mainThreadBlocked(ms: Int, phase: DiagPhase?)
    case governor(decision: DiagGovernorDecision, reason: DiagGovernorReason)
    case memoryWarning(footprintMB: Int)
    case scanEnded(outcome: DiagOutcome, seconds: Int, groupsFound: Int)
    case metricKit(kind: DiagMetricKind, summary: MetricSummary)

    /// Every JSON key the log may contain (record keys, case names, field names). A test checks the file against this.
    static let allowedKeys: Set<String> = [
        "t", "event", "value",
        "appLaunch", "scenePhase", "scanStarted", "phaseEntered", "phaseEnded", "progress", "thumbnailStats", "heartbeat",
        "stalled", "requestTimedOut", "mainThreadBlocked", "governor", "memoryWarning", "scanEnded", "metricKit",
        "version", "build", "tier", "previousRunEndedCleanly", "lastPhase", "state", "scope", "items", "phase", "units",
        "millis", "done", "total", "tried", "unavailable", "unavailablePercent", "footprintMB", "availableMB", "thermal",
        "lowPower", "inFlight", "thumbsTried", "thumbsUnavailable", "secondsSinceProgress", "pendingRequests", "kind",
        "asset", "seconds", "ms", "decision", "reason", "outcome", "groupsFound", "summary", "count", "hangDurationMs",
        "peakMemoryMB", "cpuTimeMs"
    ]
}

extension DiagPhase {
    init(_ phase: ScanPhase) {
        switch phase {
        case .idle: self = .idle
        case .inventory: self = .inventory
        case .thumbnails: self = .thumbnails
        case .candidates: self = .candidates
        case .fullResources: self = .fullResources
        case .vision: self = .vision
        case .sizing: self = .sizing
        case .finished: self = .finished
        case .cancelled: self = .cancelled
        }
    }
}

struct DiagnosticRecord: Codable, Sendable, Equatable {
    let t: Date
    let event: DiagnosticEvent
}
