import Foundation
import MachO
import os

/// Samples this process's `phys_footprint` (the number jetsam and Xcode's memory gauge use) on a background queue, so a busy
/// main thread cannot starve it. `task_info(TASK_VM_INFO)` is declared in `<mach/task_info.h>`.
final class FootprintSampler: @unchecked Sendable {
    private struct State { var peak: UInt64 = 0; var start: UInt64 = 0; var samples = 0; var timer: DispatchSourceTimer? }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let interval: Duration
    private let queue = DispatchQueue(label: "cleanslate.footprint-sampler", qos: .userInteractive)

    init(interval: Duration = .milliseconds(100)) { self.interval = interval }

    /// Current physical footprint in bytes (0 if the kernel call fails).
    static func currentBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    static func currentMB() -> Double { Double(currentBytes()) / 1_048_576 }

    /// Samples once immediately (that is `startMB`), then every `interval`.
    func start() {
        let now = Self.currentBytes()
        state.withLock { $0.peak = now; $0.start = now; $0.samples = 1 }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let nanos = interval.components.seconds * 1_000_000_000 + interval.components.attoseconds / 1_000_000_000
        timer.schedule(deadline: .now() + .nanoseconds(Int(nanos)), repeating: .nanoseconds(Int(nanos)))
        timer.setEventHandler { [state] in
            let bytes = Self.currentBytes()
            state.withLock { $0.peak = max($0.peak, bytes); $0.samples += 1 }
        }
        state.withLock { $0.timer = timer }
        timer.resume()
    }

    /// Stops sampling (one last sample is taken) and returns the peak and starting footprint in megabytes.
    func stop() -> (peakMB: Double, startMB: Double) {
        let last = Self.currentBytes()
        return state.withLock { s in
            s.timer?.cancel(); s.timer = nil
            s.peak = max(s.peak, last)
            return (Double(s.peak) / 1_048_576, Double(s.start) / 1_048_576)
        }
    }

    /// How many times the footprint was read (a sanity check that the sampler actually ran).
    var sampleCount: Int { state.withLock { $0.samples } }
}
