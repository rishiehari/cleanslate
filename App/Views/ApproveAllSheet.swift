import SwiftUI

/// Bulk approve for exact copies. Adds to the tray only; never deletes (U1).
struct ApproveAllSheet: View {
    let groups: [PhotoReviewGroup]
    let onApprove: ([PhotoReviewGroup]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var excluded: Set<String> = []

    private var included: [PhotoReviewGroup] { groups.filter { !excluded.contains($0.id) } }
    private var photoCount: Int { included.reduce(0) { $0 + $1.candidates.count } }
    private var bytes: Int64 { included.reduce(Int64(0)) { $0 + $1.estimatedVerifiedBytes } }

    var body: some View {
        NavigationStack {
            List(groups) { group in
                Toggle(isOn: Binding(get: { !excluded.contains(group.id) },
                                     set: { on in if on { excluded.remove(group.id) } else { excluded.insert(group.id) } })) {
                    HStack(spacing: Spacing.m) {
                        PhotoThumbnailView(assetID: group.keeper.id, target: 120)
                            .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: Radius.s))
                        VStack(alignment: .leading) {
                            Text("Keep 1 · delete \(group.candidates.count)").appText(.groupTitle)
                            Text(group.estimatedVerifiedBytes.friendlyBytes).appText(.secondary)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .accessibilityIdentifier("approveall.toggle.\(group.id)")
            }
            .navigationTitle("Approve all")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onApprove(included); dismiss()
                } label: {
                    Text(photoCount == 0 ? "Nothing selected" : "Approve \(photoCount) \(photoCount == 1 ? "copy" : "copies") · \(bytes.friendlyBytes)")
                        .appText(.groupTitle).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent).tint(Color.actionPrimary)
                .disabled(photoCount == 0)
                .padding(.horizontal, Spacing.m).padding(.bottom, Spacing.s)
                .accessibilityIdentifier("approveall.confirm")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("approveall.sheet")
    }
}
