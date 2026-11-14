import SwiftUI

/// The only celebration in the app (rarity rule): shown after photos were actually removed.
struct ReceiptView: View {
    let receipt: DeletionReceipt
    let onDone: () -> Void
    @State private var shownBytes: Double = 0
    @State private var showRecoverSheet = false

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            Image(systemName: receipt.verifiedRemoved > 0 ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: IconSize.hero))
                .foregroundStyle(receipt.verifiedRemoved > 0 ? Color.keepAccent : Color.warningAccent)
                .symbolEffect(.bounce, value: receipt.verifiedRemoved)
                .accessibilityHidden(true)
            Text(headline).appText(.title).multilineTextAlignment(.center)
            if receipt.verifiedRemoved > 0 {
                Text(Int64(shownBytes).friendlyBytes)
                    .appText(.heroNumber)
                    .contentTransition(.numericText(value: shownBytes))
                    .accessibilityIdentifier("receipt.bytes")
                Text("Verified file sizes removed from your library.").appText(.secondary).foregroundStyle(Color.textSecondary)
            }
            if let before = receipt.freeBytesBefore, let after = receipt.freeBytesAfter {
                Text("Free space on this device right now: \(before.friendlyBytes) → \(after.friendlyBytes)")
                    .appText(.caption).foregroundStyle(Color.textSecondary).accessibilityIdentifier("receipt.freespace")
            }
            VStack(alignment: .leading, spacing: Spacing.s) {
                Label("They're in Recently Deleted for 30 days. Empty it in Photos to free the space right away.", systemImage: "clock.arrow.circlepath")
                if receipt.uncertain > 0 {
                    Label("\(receipt.uncertain) couldn't be confirmed as removed. Check Photos.", systemImage: "questionmark.circle")
                }
                ForEach(receipt.setAside.keys.sorted(), id: \.self) { key in
                    Label(receipt.setAside[key] ?? "", systemImage: "arrow.uturn.backward.circle")
                        .foregroundStyle(Color.warningAccent)
                }
            }
            .appText(.secondary).foregroundStyle(Color.textSecondary)
            Spacer()
            Button(action: onDone) { Text("Done").frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(.glassProminent).tint(Color.actionPrimary)
                .accessibilityIdentifier("receipt.done")
        }
        .padding(Spacing.l)
        .task {
            withAnimation(.easeOut(duration: 1.0)) { shownBytes = Double(receipt.logicalBytesRemoved) }
        }
        .sheet(isPresented: $showRecoverSheet) { HowToRecoverSheet() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("receipt.screen")
    }

    private var headline: String {
        receipt.verifiedRemoved > 0
            ? "Removed \(receipt.verifiedRemoved) \(receipt.verifiedRemoved == 1 ? "photo" : "photos")"
            : "Nothing was removed"
    }
}
