import Foundation
import UIKit

/// Scene/notification-driven diagnostics hooks. Kept as testable statics so a unit test can invoke
/// exactly what the app wires.
enum DiagnosticsHooks {
    /// Spec (F02): buffered events are flushed every 5 s or when the app goes to the background.
    static func didEnterBackground(log: DiagnosticsLog = DiagnosticsLog.shared) {
        log.flush()
    }

    /// UIApplication memory warnings → `.memoryWarning` with the current footprint. Returns the
    /// observation token (the app keeps it for the process lifetime; tests remove it).
    @discardableResult
    static func observeMemoryWarnings(log: DiagnosticsLog = DiagnosticsLog.shared) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: nil) { _ in
            log.record(.memoryWarning(footprintMB: Int(MemoryProbe.footprintMB())))
        }
    }
}
