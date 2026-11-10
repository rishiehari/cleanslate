import Foundation
import MetricKit

/// Collects MetricKit *diagnostic* payloads (hangs, CPU exceptions) as numbers only: counts and durations.
/// Call stacks are deliberately dropped — they can contain symbol paths (no user data, but noise we never read).
///
/// The `MXMetricManager` subscriber API is soft-deprecated in the iOS 27 SDK ("Use MetricManager instead",
/// `API_TO_BE_DEPRECATED`) but is fully functional on iOS 26, our deployment target. It lives only in this
/// file so the later move to the Swift `MetricManager` API touches one place.
final class MetricKitCollector: NSObject, MXMetricManagerSubscriber {
    private let log: DiagnosticsLog

    init(log: DiagnosticsLog = DiagnosticsLog.shared) {
        self.log = log
        super.init()
    }

    func start() { MXMetricManager.shared.add(self) }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            if let hangs = payload.hangDiagnostics, !hangs.isEmpty {
                let totalMs = hangs.reduce(0) { $0 + Int($1.hangDuration.converted(to: .milliseconds).value) }
                log.record(.metricKit(kind: .hang, summary: MetricSummary(count: hangs.count, hangDurationMs: totalMs)))
            }
            if let exceptions = payload.cpuExceptionDiagnostics, !exceptions.isEmpty {
                let cpuMs = exceptions.reduce(0) { $0 + Int($1.totalCPUTime.converted(to: .milliseconds).value) }
                log.record(.metricKit(kind: .cpuException, summary: MetricSummary(count: exceptions.count, cpuTimeMs: cpuMs)))
            }
        }
    }
}
