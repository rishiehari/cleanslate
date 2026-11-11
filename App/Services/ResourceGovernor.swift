import Foundation
import os

/// Keeps a long scan from cooking the phone or starving the system: pauses when the device is
/// hot or memory is low, slows down in Low Power Mode, and tells the user why (U15).
@MainActor
final class ResourceGovernor: ObservableObject {
    struct Inputs: Sendable {
        var thermalState: @Sendable () -> ProcessInfo.ThermalState
        var availableMemoryBytes: @Sendable () -> Int
        var lowPowerMode: @Sendable () -> Bool
        var memoryPressure: @Sendable () -> MemoryPressure
        var sleep: @Sendable (Duration) async -> Void

        static let live = Inputs(
            thermalState: { ProcessInfo.processInfo.thermalState },
            availableMemoryBytes: { os_proc_available_memory() },
            lowPowerMode: { ProcessInfo.processInfo.isLowPowerModeEnabled },
            memoryPressure: { MemoryPressureMonitor.shared.currentLevel },
            sleep: { try? await Task.sleep(for: $0) })
    }

    enum Decision: Equatable {
        case proceed(concurrency: Int)
        /// The device is too hot to continue; progress is saved and the user can resume.
        case stop(reason: String)
    }

    @Published private(set) var pauseReason: String?
    @Published private(set) var isLowPower = false
    /// Feature commits per batch under memory pressure (base 100; `.warning` quarters it).
    @Published private(set) var batchSize = ResourceGovernor.baseBatchSize
    /// Called once when pressure rises to `.warning` or above: the engine drops its caches.
    var dropCachesRequested: (@MainActor () -> Void)?
    /// Local diagnostics; decisions are logged on change only (checkpoint runs per item).
    var diagnostics: DiagnosticsLog?

    private let inputs: Inputs
    private let cores: Int
    static let lowMemoryBytes = 150 * 1024 * 1024
    /// Below this, the scan pauses to free memory regardless of tier (F03). Real devices only:
    /// the simulator's `os_proc_available_memory()` is unreliable, so the floor never triggers
    /// there (the memory-Pressure input still works on every platform).
    static let criticalMemoryBytes = 100 * 1024 * 1024
    static func isCriticallyLowMemory(_ bytes: Int) -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return bytes < criticalMemoryBytes
        #endif
    }
    /// How long memory pressure may pause the scan before it stops with progress saved.
    static let memoryPauseSeconds = 60
    static let baseBatchSize = 100
    /// How long to wait for a warm phone to cool before giving up (seconds).
    private let maximumPauseSeconds: Int

    init(inputs: Inputs = .live, cores: Int = ProcessInfo.processInfo.activeProcessorCount, maximumPauseSeconds: Int = 600) {
        self.inputs = inputs
        self.cores = cores
        self.maximumPauseSeconds = maximumPauseSeconds
    }

    private var baseConcurrency: Int { max(1, min(4, cores / 2)) }

    /// Call between batches. Returns how wide to work, waits while the device is warm or short
    /// of memory, or says stop. Memory: `.warning` shrinks batches and width; `.critical` (or
    /// < 100 MB available) pauses up to 60 s, then stops with progress saved.
    func checkpoint() async -> Decision {
        var waited = 0
        while true {
            if Task.isCancelled { setPauseReason(nil); return .proceed(concurrency: 1) }
            isLowPower = inputs.lowPowerMode()
            let pressure = inputs.memoryPressure()
            batchSize = pressure >= .warning ? max(1, Self.baseBatchSize / 4) : Self.baseBatchSize
            if pressure >= .warning {
                if !cachesDroppedForEpisode { cachesDroppedForEpisode = true; dropCachesRequested?() }   // once per episode
            } else {
                cachesDroppedForEpisode = false
            }
            let lowMemory = Self.isCriticallyLowMemory(Int(inputs.availableMemoryBytes()))
            if pressure == .critical || lowMemory {
                setPauseReason("Paused to free memory. Your progress is saved.")
                logDecision(.pause, .lowMemory)
                if waited >= Self.memoryPauseSeconds {
                    setPauseReason(nil)
                    logDecision(.stop, .lowMemory)
                    return .stop(reason: "Paused to free memory. Your progress is saved.")
                }
                await inputs.sleep(.seconds(2)); waited += 2
                continue
            }
            switch inputs.thermalState() {
            case .critical:
                setPauseReason(nil)
                logDecision(.stop, .thermal)
                return .stop(reason: "Stopped because your iPhone is very warm. Your progress is saved. Scan again when it has cooled down.")
            case .serious:
                setPauseReason("Paused — your iPhone is warm")
                logDecision(.pause, .thermal)
                if waited >= maximumPauseSeconds {
                    setPauseReason(nil)
                    logDecision(.stop, .thermal)
                    return .stop(reason: "Stopped because your iPhone stayed warm. Your progress is saved. Scan again later.")
                }
                await inputs.sleep(.seconds(2)); waited += 2
                continue
            case .fair:
                setPauseReason(nil)
                logDecision(.shrink, .thermal)
                return .proceed(concurrency: min(2, baseConcurrency))
            default:
                break
            }
            if pressure >= .warning {
                setPauseReason(nil)
                logDecision(.shrink, .lowMemory)
                return .proceed(concurrency: 1)
            }
            if inputs.availableMemoryBytes() < Self.lowMemoryBytes {
                setPauseReason(nil)
                logDecision(.shrink, .lowMemory)
                return .proceed(concurrency: 1)
            }
            setPauseReason(nil)
            if isLowPower, baseConcurrency > 2 { logDecision(.shrink, .lowPower) }
            return .proceed(concurrency: isLowPower ? min(2, baseConcurrency) : baseConcurrency)
        }
    }

    private var lastLoggedDecision: (decision: DiagGovernorDecision, reason: DiagGovernorReason)?
    private var cachesDroppedForEpisode = false
    /// @Published fires on every assignment; checkpoints run per item, so only real changes publish.
    private func setPauseReason(_ value: String?) {
        if pauseReason != value { pauseReason = value }
    }

    /// One event per decision CHANGE: checkpoint runs per item, so unchanged decisions stay silent.
    private func logDecision(_ decision: DiagGovernorDecision, _ reason: DiagGovernorReason) {
        if let last = lastLoggedDecision, last.decision == decision, last.reason == reason { return }
        lastLoggedDecision = (decision, reason)
        diagnostics?.record(.governor(decision: decision, reason: reason))
    }
}
