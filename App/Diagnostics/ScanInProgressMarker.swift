import Foundation

/// A flag in `LibraryStore.meta` that says a scan was still running the last time the process died.
/// Written at every phase boundary, cleared on every outcome path: a leftover flag therefore means the app
/// was killed mid-scan (force-quit, jetsam) and the next launch logs `appLaunch(previousRunEndedCleanly: false)`.
enum ScanInProgressMarker {
    static let metaKey = "scan.inProgress"

    /// Phase name + wall-clock only: no photo information.
    struct Value: Codable, Equatable {
        var phase: DiagPhase
        var at: Date
    }

    static func set(_ phase: DiagPhase, in store: LibraryStore) async {
        let data = try? JSONEncoder().encode(Value(phase: phase, at: Date()))
        try? await store.setMeta(metaKey, data)
    }

    static func read(in store: LibraryStore) async -> Value? {
        await store.meta(metaKey).flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
    }

    /// Every engine outcome (finished, paused, stopped) ends the run without a kill, so the marker goes away.
    static func clear(in store: LibraryStore) async {
        try? await store.setMeta(metaKey, nil)
    }
}
