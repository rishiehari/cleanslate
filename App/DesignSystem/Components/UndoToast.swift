import SwiftUI

/// Short-lived confirmation with Undo (U8/U15). The caller owns the dismiss timer.
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            Text(message).appText(.secondary)
            Button("Undo", action: onUndo)
                .appText(.groupTitle)
                .accessibilityIdentifier("toast.undo")
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s + Spacing.xs)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toast")
    }
}

#Preview("Toast") {
    ZStack { Color.surfaceBackground; UndoToast(message: "Approved 3 copies", onUndo: {}) }
}
