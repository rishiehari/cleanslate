import SwiftUI

/// Solid content actions keep explicit contrast in enabled and disabled states.
/// Disabled actions retain a readable label and a border; model guards still own availability.
struct AccessiblePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.onAccent : Color.textSecondary)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .background(isEnabled ? Color.actionPrimary : Color.surfaceCard, in: Capsule())
            .overlay { Capsule().stroke(isEnabled ? Color.clear : Color.textSecondary, lineWidth: Spacing.xxs) }
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}
