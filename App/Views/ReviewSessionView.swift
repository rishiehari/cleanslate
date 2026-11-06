import SwiftUI

/// Walks through a queue of groups: Approve or Skip opens the next one, so a long inbox
/// is one smooth pass instead of "back, tap the next row" 200 times.
/// Always shows the LATEST version of a group: if the library changed underneath it, the screen refreshes
/// (or says the group was removed) instead of showing stale photos.
struct ReviewSessionView: View {
    @EnvironmentObject private var model: CleaningViewModel
    let groups: [PhotoReviewGroup]
    let tray: DeletionTray
    @State private var index = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let original = groups[index]
        let position = groups.count > 1 ? "\(index + 1) of \(groups.count)" : nil
        if let current = model.groups.first(where: { $0.id == original.id }) {
            ReviewGroupView(group: current, tray: tray, analyzer: model.analyzer, position: position, onFinished: advance)
                .id(Self.token(current))      // a changed group starts a fresh review
        } else {
            ContentStateView<Int, EmptyView>(state: .empty(
                title: "This group changed",
                message: "The photos changed, so it was taken off your list. Nothing was deleted.")) { _ in EmptyView() }
                .overlay(alignment: .bottom) {
                    Button("Next group", action: advance).buttonStyle(.glassProminent).tint(Color.actionPrimary)
                        .padding(Spacing.l).accessibilityIdentifier("review.gone.next")
                }
                .background(Color.surfaceBackground)
                .navigationTitle(position ?? "Review")
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("review.gone")
        }
    }

    private func advance() {
        if index + 1 < groups.count { index += 1 } else { dismiss() }
    }

    private static func token(_ group: PhotoReviewGroup) -> String {
        group.all.map { "\($0.id):\($0.record.revision)" }.joined(separator: "|")
    }
}
