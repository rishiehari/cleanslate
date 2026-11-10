import Foundation

/// Scene-driven diagnostics hooks. Kept as testable statics so a unit test can invoke exactly
/// what the app runs on a scene transition.
enum DiagnosticsHooks {
    /// Spec (F02): buffered events are flushed every 5 s or when the app goes to the background.
    static func didEnterBackground(log: DiagnosticsLog = DiagnosticsLog.shared) {
        log.flush()
    }
}
