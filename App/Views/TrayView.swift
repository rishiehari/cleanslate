import SwiftUI

/// Everything the user approved, ready for the final delete. Anything can still be removed (U1, U15).
struct TrayView: View {
    @EnvironmentObject private var model: CleaningViewModel
    @ObservedObject var tray: DeletionTray
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false
    @State private var confirmClear = false
    @State private var deleteTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if tray.isEmpty {
                    ContentUnavailableView("Your tray is empty", systemImage: "tray",
                        description: Text("Approve photos in a review and they'll wait here. Nothing is deleted until you confirm."))
                } else {
                    List {
                        if !tray.needsAttention.isEmpty {
                            Section {
                                ForEach(tray.entries.filter { tray.needsAttention[$0.id] != nil }) { entry in attentionRow(id: entry.id, thumbnailID: entry.group.keeper.id) }
                                ForEach(tray.standaloneEntries.filter { tray.needsAttention[$0.id] != nil }) { entry in
                                    attentionRow(id: entry.id, thumbnailID: entry.items.first?.id ?? "")
                                }
                            } header: {
                                Text("Needs another look")
                            } footer: {
                                Text("These changed after you approved them, so they won't be deleted unless you review them again.")
                            }
                            .accessibilityIdentifier("tray.attention")
                        }
                        Section {
                            ForEach(tray.readyEntries) { entry in row(entry) }
                            ForEach(tray.readyStandaloneEntries) { entry in standaloneRow(entry) }
                        } footer: {
                            Text("Swipe a group to take it out of the tray.")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Ready to delete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                if !tray.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", role: .destructive) { confirmClear = true }
                            .accessibilityIdentifier("tray.clear")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if tray.hasReadyItems {
                    Button { confirming = true } label: {
                        Text("Delete \(tray.photoCount) \(tray.photoCount == 1 ? "photo" : "photos")")
                            .appText(.groupTitle).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.deleteAccent)
                    .padding(.horizontal, Spacing.m).padding(.bottom, Spacing.s)
                    .accessibilityIdentifier("tray.delete")
                }
            }
            .sheet(isPresented: $confirming) {
                ConfirmSheet(photoCount: tray.photoCount, verifiedBytes: tray.verifiedBytes,
                             isWorking: tray.isDeleting, promptCount: tray.promptCount, progress: tray.checkProgress,
                             onConfirm: {
                                 deleteTask = Task {
                                     let removed = await model.deleteTray()
                                     confirming = false
                                     if removed { dismiss() }          // the receipt is shown by Home
                                 }
                             },
                             onCancel: { deleteTask?.cancel(); confirming = false })
            }
            .alert("Not deleted", isPresented: Binding(get: { tray.batchNotice != nil }, set: { if !$0 { tray.batchNotice = nil } })) {
                Button("OK") { tray.batchNotice = nil }
            } message: {
                Text(tray.batchNotice ?? "")
            }
            .alert("Empty the tray?", isPresented: $confirmClear) {
                Button("Cancel", role: .cancel) {}
                Button("Empty tray", role: .destructive) { tray.clear() }
            } message: {
                Text("Your photos aren't touched. They just leave the tray.")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tray.screen")
    }

    private func attentionRow(id: String, thumbnailID: String) -> some View {
        HStack(spacing: Spacing.m) {
            PhotoThumbnailView(assetID: thumbnailID, target: 160)
                .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: Radius.s))
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(tray.needsAttention[id] ?? "").appText(.groupTitle)
                Button("Review again") { tray.sendBackToReview(id) }
                    .appText(.secondary).accessibilityIdentifier("tray.reviewagain.\(id)")
            }
        }
        .swipeActions { Button("Remove", role: .destructive) { tray.remove(groupID: id) } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tray.attention.\(id)")
    }

    private func standaloneRow(_ entry: StandaloneTrayEntry) -> some View {
        HStack(spacing: Spacing.m) {
            if let first = entry.items.first {
                PhotoThumbnailView(assetID: first.id, target: 160)
                    .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: Radius.s))
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("\(entry.items.count) \(entry.items.count == 1 ? "item" : "items") to delete").appText(.groupTitle)
                Text(entry.verifiedBytes > 0 ? "\(entry.verifiedBytes.friendlyBytes) verified" : "Size not measured")
                    .appText(.secondary).foregroundStyle(Color.textSecondary)
            }
        }
        .swipeActions { Button("Remove", role: .destructive) { tray.remove(groupID: entry.id) } }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tray.row.\(entry.id)")
    }

    private func row(_ entry: TrayEntry) -> some View {
        HStack(spacing: Spacing.m) {
            PhotoThumbnailView(assetID: entry.group.keeper.id, target: 160)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: Radius.s))
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("\(entry.selectedIDs.count) \(entry.selectedIDs.count == 1 ? "copy" : "photos") to delete")
                    .appText(.groupTitle)
                Text(entry.verifiedBytes > 0 ? "\(entry.verifiedBytes.friendlyBytes) verified · keeping 1" : "Keeping 1")
                    .appText(.secondary).foregroundStyle(Color.textSecondary)
            }
        }
        .swipeActions {
            Button("Remove", role: .destructive) { tray.remove(groupID: entry.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tray.row.\(entry.id)")
    }
}
