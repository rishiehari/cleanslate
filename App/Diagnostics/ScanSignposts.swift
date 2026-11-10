import Foundation
import os

/// Intervals for Instruments (Points of Interest / os_signpost). Phase names only; no photo information.
enum ScanSignposts {
    static let signposter = OSSignposter(subsystem: "org.cleanslate.free", category: "scan")

    static func begin(_ phase: DiagPhase) -> OSSignpostIntervalState {
        signposter.beginInterval("scanPhase", id: signposter.makeSignpostID(), "\(phase.rawValue, privacy: .public)")
    }

    static func end(_ state: OSSignpostIntervalState) { signposter.endInterval("scanPhase", state) }
}
