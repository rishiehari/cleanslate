import Foundation
import os

/// What the scan is doing right now, readable from any thread. The engine writes it; the heartbeat and the watchdog read it,
/// so both keep working even while the main thread is blocked. Numbers and a phase only.
final class ScanCounters: Sendable {
    struct Snapshot: Sendable, Equatable {
        var phase: DiagPhase = .idle
        var done = 0, total = 0, inFlight = 0, thumbsTried = 0, thumbsUnavailable = 0
        var thumbnailUnavailablePercent: Int { thumbsTried == 0 ? 0 : thumbsUnavailable * 100 / thumbsTried }
    }
    private let state = OSAllocatedUnfairLock(initialState: Snapshot())

    var snapshot: Snapshot { state.withLock { $0 } }
    func update(_ change: @Sendable (inout Snapshot) -> Void) { state.withLock { change(&$0) } }
    func reset() { state.withLock { $0 = Snapshot() } }
}

/// Writes a `heartbeat` event every 2 s during a scan (HANG_RCA_DEVICE_LOG: a stall must be visible without Xcode), and a
/// `stalled` event when `done` has not moved for `stallAfter` seconds. Runs off the main actor on purpose.
final class ScanHeartbeat: @unchecked Sendable {
    struct Probes: Sendable {
        var footprintMB: @Sendable () -> Int = { Int(MemoryProbe.footprintMB()) }
        var availableMB: @Sendable () -> Int = { Int(MemoryProbe.availableMB()) }
        var thermal: @Sendable () -> Int = { ProcessInfo.processInfo.thermalState.rawValue }
        var lowPower: @Sendable () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled }
        var seconds: @Sendable () -> Double = { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }
    }

    static let interval: Duration = .seconds(2)
    private let log: DiagnosticsLog
    private let counters: ScanCounters
    private let probes: Probes
    private let stallAfter: Int
    private struct Progress { var lastDone = -1; var lastChange: Double = 0; var task: Task<Void, Never>? }
    private let progress = OSAllocatedUnfairLock(initialState: Progress())

    init(log: DiagnosticsLog, counters: ScanCounters, probes: Probes = Probes(), stallAfter: Int = 6) {
        self.log = log; self.counters = counters; self.probes = probes; self.stallAfter = stallAfter
    }

    func start(interval: Duration = ScanHeartbeat.interval) {
        stop()
        let now = probes.seconds()
        progress.withLock { $0.lastDone = -1; $0.lastChange = now }
        let task = Task.detached(priority: .utility) { [self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { break }
                beat()
            }
        }
        progress.withLock { $0.task = task }
    }

    func stop() { progress.withLock { $0.task?.cancel(); $0.task = nil } }

    /// One heartbeat (the timer calls this; tests call it directly).
    func beat() {
        let s = counters.snapshot
        log.record(.heartbeat(phase: s.phase, done: s.done, total: s.total, footprintMB: probes.footprintMB(), availableMB: probes.availableMB(),
                              thermal: probes.thermal(), lowPower: probes.lowPower(), inFlight: s.inFlight,
                              thumbsTried: s.thumbsTried, thumbsUnavailable: s.thumbsUnavailable))
        let now = probes.seconds()
        let stalledFor: Int? = progress.withLock { p in
            if p.lastDone != s.done { p.lastDone = s.done; p.lastChange = now; return nil }
            let idle = Int(now - p.lastChange)
            return idle >= stallAfter ? idle : nil
        }
        if let stalledFor { log.record(.stalled(phase: s.phase, secondsSinceProgress: stalledFor, pendingRequests: s.inFlight)) }
    }
}
