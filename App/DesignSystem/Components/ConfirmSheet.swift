import SwiftUI

/// Final in-app summary before Apple's own prompt (U1). Never deletes by itself.
struct ConfirmSheet: View {
    let photoCount: Int
    let verifiedBytes: Int64
    let isWorking: Bool
    var promptCount = 1
    /// (checked, total) while the originals are rechecked before Apple's prompt.
    var progress: (done: Int, total: Int)?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var workingTitle: String {
        guard isWorking else { return "Continue" }
        if let progress, progress.total > 0 { return "Double-checking \(min(progress.done + 1, progress.total)) of \(progress.total)…" }
        return "Double-checking…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Delete \(photoCount) photos?").appText(.title)
            Text("That frees about \(verifiedBytes.friendlyBytes) (verified file sizes).")
                .appText(.body)
            VStack(alignment: .leading, spacing: Spacing.s) {
                Label("Deleted photos stay in Recently Deleted for 30 days.", systemImage: "clock.arrow.circlepath")
                Label("With iCloud Photos on, they're removed from your other devices too.", systemImage: "icloud")
                Label(promptCount > 1 ? "Because there are so many, Apple will ask you to confirm \(promptCount) times." : "Apple will ask you to confirm next.",
                      systemImage: "hand.raised")
            }
            .appText(.secondary).foregroundStyle(Color.textSecondary)

            Spacer(minLength: Spacing.s)
            Button(action: onConfirm) {
                HStack {
                    if isWorking { ProgressView().tint(.white) }
                    Text(workingTitle).frame(maxWidth: .infinity)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.deleteAccent)
            .disabled(isWorking)
            .accessibilityIdentifier("confirm.continue")

            Button("Cancel", role: .cancel, action: onCancel)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("confirm.cancel")
        }
        .padding(Spacing.l)
        .presentationDetents([.medium])
        .presentationBackground(Color.surfaceBackground)   // solid, so the tray behind never shows through "Cancel"
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("confirm.sheet")
    }
}

#Preview("Confirm") {
    ConfirmSheet(photoCount: 214, verifiedBytes: 3_100_000_000, isWorking: true, progress: (12, 214), onConfirm: {}, onCancel: {})
}
