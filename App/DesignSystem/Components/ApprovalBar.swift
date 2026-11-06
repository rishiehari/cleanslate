import SwiftUI

/// Floating Skip / Approve bar. Liquid Glass on the navigation layer only, one container (U7).
struct ApprovalBar: View {
    let approveTitle: String
    var subtitle: String?
    let canApprove: Bool
    let onSkip: () -> Void
    let onApprove: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                Button(action: onSkip) {
                    Text("Skip").appText(.groupTitle).padding(.horizontal, Spacing.s)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("approval.skip")

                Button(action: onApprove) {
                    VStack(spacing: Spacing.xxs) {
                        Text(approveTitle).appText(.groupTitle)
                        if let subtitle { Text(subtitle).appText(.caption) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.actionPrimary)
                .disabled(!canApprove)
                .accessibilityIdentifier("approval.approve")
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.bottom, Spacing.s)
    }
}

#Preview("Approval bar") {
    ZStack(alignment: .bottom) {
        Color.surfaceBackground.ignoresSafeArea()
        ApprovalBar(approveTitle: "Approve 3 copies", subtitle: "38 MB", canApprove: true, onSkip: {}, onApprove: {})
    }
}
