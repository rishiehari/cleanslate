import Foundation
import MachO
import os

/// Memory numbers for the heartbeat: one `task_info` call plus `os_proc_available_memory()`.
enum MemoryProbe {
    /// This process's `phys_footprint` (the number jetsam and Xcode's gauge use), in bytes. 0 if the kernel call fails.
    static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    static func footprintMB() -> Double { Double(footprintBytes()) / 1_048_576 }

    /// Memory this process may still use before the system terminates it. The simulator may report 0.
    static func availableMB() -> Double { Double(max(0, os_proc_available_memory())) / 1_048_576 }
}
