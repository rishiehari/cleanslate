import Foundation
import os

/// Watches the main thread from a utility queue (HANG_RCA H3: a frozen UI must be visible in the on-device
/// log without Xcode attached). Every second it posts a trivial block to the main queue and measures how long
/// the reply takes; a reply slower than `thresholdMs` means the main thread was unresponsive that second.
/// At most one `mainThreadBlocked` event per `throttleSeconds` is recorded, with the current scan phase.
final class MainThreadWatchdog: @unchecked Sendable {
    struct Probes: Sendable {
        /// Round-trip time to the main queue in milliseconds (a real hop by default; a constant in tests).
        var latencyMs: @Sendable () -> Int = MainThreadWatchdog.measureMainThreadLatency
        var now: @Sendable () -> Double = { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }
        /// Current scan phase, read from the lock-protected counters (never from main-actor state).
        var phase: @Sendable () -> DiagPhase? = { nil }
    }

    static let thresholdMs = 250
    static let throttleSeconds: Double = 5
    static let interval = DispatchTimeInterval.seconds(1)

    private let log: DiagnosticsLog
    private let probes: Probes
    private let queue = DispatchQueue(label: "org.cleanslate.watchdog", qos: .utility)
    private struct State { var timer: DispatchSourceTimer?; var lastEventAt = -MainThreadWatchdog.throttleSeconds }
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(log: DiagnosticsLog, probes: Probes = Probes()) {
        self.log = log; self.probes = probes
    }

    deinit { state.withLock { $0.timer?.cancel() } }

    func start() {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.interval, repeating: Self.interval)
        timer.setEventHandler { [weak self] in self?.check() }
        state.withLock { $0.timer = timer }
        timer.resume()
    }

    func stop() { state.withLock { $0.timer?.cancel(); $0.timer = nil } }

    /// One measurement; the timer calls this every second, tests call it directly.
    func check() {
        let ms = probes.latencyMs()
        guard ms > Self.thresholdMs else { return }
        let now = probes.now()
        let shouldRecord = state.withLock { s -> Bool in
            guard now - s.lastEventAt >= Self.throttleSeconds else { return false }
            s.lastEventAt = now
            return true
        }
        if shouldRecord { log.record(.mainThreadBlocked(ms: ms, phase: probes.phase())) }
    }

    /// Posts an empty block to the main queue and waits for it; the wait IS how blocked the main thread is.
    /// Runs on the utility queue only, so a stuck main thread stalls this measurement, nothing else.
    static func measureMainThreadLatency() -> Int {
        let semaphore = DispatchSemaphore(value: 0)
        let start = DispatchTime.now()
        DispatchQueue.main.async { semaphore.signal() }
        semaphore.wait()
        return Int(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    }
}
