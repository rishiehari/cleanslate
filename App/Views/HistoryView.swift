import SwiftUI

/// Everything CleanSlate has deleted for you, with the honest storage numbers.
struct HistoryView: View {
    @EnvironmentObject private var model: CleaningViewModel
    @State private var receipts: [DeletionReceipt] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if loaded && receipts.isEmpty {
                ContentUnavailableView("Nothing deleted yet", systemImage: "clock.arrow.circlepath",
                    description: Text("When you delete photos with CleanSlate, a record shows up here."))
            } else {
                List {
                    Section {
                        ForEach(receipts) { receipt in row(receipt) }
                    } footer: {
                        Text("Deleted photos stay in Recently Deleted for 30 days. Space on this device and in iCloud is freed after they're removed from there. Free-space numbers are measurements taken at the time.")
                        NavigationLink("How to get photos back", destination: HowToRecoverSheet())
                            .accessibilityIdentifier("history.recover.link")
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .task { receipts = await model.loadHistory(); loaded = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.screen")
    }

    private func row(_ receipt: DeletionReceipt) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Removed \(receipt.verifiedRemoved) \(receipt.verifiedRemoved == 1 ? "photo" : "photos")").appText(.groupTitle)
            Text("\(receipt.logicalBytesRemoved.friendlyBytes) of verified file sizes · \(receipt.date.formatted(date: .abbreviated, time: .shortened))")
                .appText(.secondary).foregroundStyle(Color.textSecondary)
            if let before = receipt.freeBytesBefore, let after = receipt.freeBytesAfter {
                Text("Free space on this device: \(before.friendlyBytes) → \(after.friendlyBytes)")
                    .appText(.caption).foregroundStyle(Color.textSecondary)
            }
            if receipt.uncertain > 0 {
                Text("\(receipt.uncertain) couldn't be confirmed as removed.").appText(.caption).foregroundStyle(Color.warningAccent)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
