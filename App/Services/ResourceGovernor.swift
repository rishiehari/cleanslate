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
        var sleep: @Sendable (Duration) async -> Void

        static let live = Inputs(
            thermalState: { ProcessInfo.processInfo.thermalState },
            availableMemoryBytes: { os_proc_available_memory() },
            lowPowerMode: { ProcessInfo.processInfo.isLowPowerModeEnabled },
            sleep: { try? await Task.sleep(for: $0) })
    }

    enum Decision: Equatable {
        case proceed(concurrency: Int)
        /// The device is too hot to continue; progress is saved and the user can resume.
        case stop(reason: String)
    }

    @Published private(set) var pauseReason: String?
    @Published private(set) var isLowPower = false

    private let inputs: Inputs
    private let cores: Int
    static let lowMemoryBytes = 150 * 1024 * 1024
    /// How long to wait for a warm phone to cool before giving up (seconds).
    private let maximumPauseSeconds: Int

    init(inputs: Inputs = .live, cores: Int = ProcessInfo.processInfo.activeProcessorCount, maximumPauseSeconds: Int = 600) {
        self.inputs = inputs
        self.cores = cores
        self.maximumPauseSeconds = maximumPauseSeconds
    }

    private var baseConcurrency: Int { max(1, min(4, cores / 2)) }

    /// Call between batches. Returns how wide to work, waits while the device is warm, or says stop.
    func checkpoint() async -> Decision {
        var waited = 0
        while true {
            if Task.isCancelled { pauseReason = nil; return .proceed(concurrency: 1) }
            isLowPower = inputs.lowPowerMode()
            switch inputs.thermalState() {
            case .critical:
                pauseReason = nil
                return .stop(reason: "Stopped because your iPhone is very warm. Your progress is saved. Scan again when it has cooled down.")
            case .serious:
                pauseReason = "Paused — your iPhone is warm"
                if waited >= maximumPauseSeconds {
                    pauseReason = nil
                    return .stop(reason: "Stopped because your iPhone stayed warm. Your progress is saved. Scan again later.")
                }
                await inputs.sleep(.seconds(2)); waited += 2
                continue
            case .fair:
                pauseReason = nil
                return .proceed(concurrency: min(2, baseConcurrency))
            default:
                break
            }
            if inputs.availableMemoryBytes() < Self.lowMemoryBytes {
                pauseReason = nil
                return .proceed(concurrency: 1)
            }
            pauseReason = nil
            return .proceed(concurrency: isLowPower ? min(2, baseConcurrency) : baseConcurrency)
        }
    }
}
