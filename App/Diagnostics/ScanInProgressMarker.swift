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

// MARK: - Launch

enum DiagnosticsLaunch {
    /// Records the `appLaunch` event. A leftover `scan.inProgress` marker means the previous process was killed
    /// mid-scan (force-quit, jetsam), so it is reported as not ended cleanly; the marker is consumed either way,
    /// because it described the previous process, not this one.
    static func recordAppLaunch(store: LibraryStore, log: DiagnosticsLog) async {
        let marker = await ScanInProgressMarker.read(in: store)
        await ScanInProgressMarker.clear(in: store)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        log.record(.appLaunch(version: version, build: build, tier: DeviceTier.current,
                              previousRunEndedCleanly: marker == nil, lastPhase: marker?.phase))
    }
}
