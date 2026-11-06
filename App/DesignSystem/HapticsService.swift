import UIKit

/// Semantic haptic vocabulary (U9). Fired ONLY from view models, never from views.
/// `batchDeleted` is the rarest and biggest pattern; nothing else uses it.
enum HapticEvent: Equatable {
    case toggle, approve, skip, undo, blocked, batchDeleted
}

@MainActor
final class HapticsService {
    static let shared = HapticsService()
    static let defaultsKey = "haptics.enabled"

    /// Test seam: records events instead of vibrating.
    var recorder: ((HapticEvent) -> Void)?

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.defaultsKey) }
    }

    private lazy var selection = UISelectionFeedbackGenerator()
    private lazy var impact = UIImpactFeedbackGenerator(style: .light)
    private lazy var notify = UINotificationFeedbackGenerator()

    func fire(_ event: HapticEvent, enabled: Bool? = nil) {
        guard enabled ?? isEnabled else { return }
        recorder?(event)
        switch event {
        case .toggle: selection.selectionChanged()
        case .skip: impact.impactOccurred(intensity: 0.5)
        case .undo: impact.impactOccurred(intensity: 0.7)
        case .approve: notify.notificationOccurred(.success)
        case .blocked: notify.notificationOccurred(.warning)
        case .batchDeleted:
            notify.notificationOccurred(.success)
            Task { @MainActor [impact] in
                try? await Task.sleep(for: .milliseconds(120))
                impact.impactOccurred(intensity: 1)
            }
        }
    }
}
