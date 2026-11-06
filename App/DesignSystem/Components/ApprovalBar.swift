import SwiftUI

/// Floating Skip / Approve bar. Liquid Glass on the navigation layer only, one container (U7).
struct ApprovalBar: View {
    let approveTitle: String
    var subtitle: String?
    let canApprove: Bool
    let onSkip: () -> Void
    let onApprove: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var label: String { subtitle.map { "\(approveTitle) · \($0)" } ?? approveTitle }

    var body: some View {
        GlassEffectContainer(spacing: Spacing.m) {
            // At accessibility text sizes the two buttons stack, so neither label is squeezed.
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Spacing.s)) : AnyLayout(HStackLayout(spacing: Spacing.m))
            layout {
                if typeSize.isAccessibilitySize { approveButton; skipButton } else { skipButton; approveButton }
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.top, Spacing.m)
        .padding(.bottom, Spacing.s)
        // Fade the scrolling photos out behind the controls so labels stay legible (plain fill, not glass).
        .background(alignment: .bottom) {
            LinearGradient(stops: [.init(color: Color.surfaceBackground.opacity(0), location: 0),
                                   .init(color: Color.surfaceBackground.opacity(0.96), location: 0.4),
                                   .init(color: Color.surfaceBackground, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var skipButton: some View {
        Button(action: onSkip) {
            Text("Skip").appText(.groupTitle).foregroundStyle(.primary).padding(.horizontal, Spacing.s)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, minHeight: 44)
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("approval.skip")
    }

    private var approveButton: some View {
        Button(action: onApprove) {
            Text(label)
                .appText(.groupTitle)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.actionPrimary)
        .disabled(!canApprove)
        .accessibilityIdentifier("approval.approve")
    }
}

#Preview("Approval bar") {
    ZStack(alignment: .bottom) {
        Color.surfaceBackground.ignoresSafeArea()
        ApprovalBar(approveTitle: "Approve 3 copies", subtitle: "38 MB", canApprove: true, onSkip: {}, onApprove: {})
    }
}
