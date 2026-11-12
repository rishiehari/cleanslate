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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if AdaptiveLayout.showsReviewQueue(width: proxy.size.width,
                                                   accessibilityText: dynamicTypeSize.isAccessibilitySize) {
                    queue
                        .frame(width: AdaptiveLayout.reviewQueueWidth)
                    Divider()
                }
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// The queue is context, not another approval surface. Review advances only through
    /// the existing Approve/Skip controls, preserving the active draft during resizing.
    private var queue: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Review queue").appText(.groupTitle)
                    Text("Approve or skip to move to the next group.")
                        .appText(.caption).foregroundStyle(Color.textSecondary)
                    ForEach(Array(groups.enumerated()), id: \.element.id) { position, original in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            if let current = model.groups.first(where: { $0.id == original.id }) {
                                GroupRowView(group: current, status: position == index ? "Reviewing now"
                                    : position < index ? "Reviewed" : "Up next", showsDisclosure: false)
                            } else {
                                Label("Group changed", systemImage: "exclamationmark.circle")
                                    .appText(.secondary).padding(Spacing.m)
                            }
                        }
                        .overlay {
                            if position == index {
                                RoundedRectangle(cornerRadius: Radius.m)
                                    .stroke(Color.actionPrimary, lineWidth: Spacing.xxs)
                            }
                        }
                        .accessibilityAddTraits(position == index ? .isSelected : [])
                        .accessibilityIdentifier("review.queue.\(original.id)")
                        .id(position)
                    }
                }
                .padding(Spacing.m)
            }
            .onAppear { scroll.scrollTo(index, anchor: .center) }
            .onChange(of: index) { _, next in scroll.scrollTo(next, anchor: .center) }
        }
        .background(Color.surfaceBackground)
        .accessibilityIdentifier("review.queue")
    }

    @ViewBuilder private var detail: some View {
        if groups.isEmpty {
            ContentUnavailableView("No groups to review", systemImage: "checkmark.circle")
        } else {
            activeGroup
        }
    }

    @ViewBuilder private var activeGroup: some View {
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
