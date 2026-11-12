import Foundation
import CleanSlateCore
@testable import CleanSlate

/// A hand-driven `ProtectionGate` for coordinator, tray and suggestion tests (N05 C4+).
@MainActor
final class StaticProtectionGate: ProtectionGate {
    var availability: ProtectionAvailability = .ready
    var revision: Int64 = 1
    var pendingWrites = 0
    var protectedIDs: Set<String> = []
    /// Called on every `verdict(for:)`, so a test can change the gate in the middle of a commit.
    var onVerdict: ((PhotoSnapshot) -> Void)?

    init(protected: Set<String> = []) { protectedIDs = protected }

    func verdict(for snapshot: PhotoSnapshot) -> ProtectionVerdict {
        onVerdict?(snapshot)
        if availability == .ready, pendingWrites > 0 { return .indeterminate(.ruleWritePending) }
        return ruleVerdict(for: snapshot)
    }

    func ruleVerdict(for snapshot: PhotoSnapshot) -> ProtectionVerdict {
        switch availability {
        case .loading: return .indeterminate(.rulesLoading)
        case .unavailable, .lost: return .indeterminate(.rulesUnavailable)
        case .ready: break
        }
        return protectedIDs.contains(snapshot.id) ? .protected(ruleIDs: [UUID()]) : .unprotected
    }
}
