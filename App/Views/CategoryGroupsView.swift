import SwiftUI
import CleanSlateCore

/// The review inbox for one category. Groups appear as they're found (U12).
struct CategoryGroupsView: View {
    @EnvironmentObject private var model: CleaningViewModel
    @EnvironmentObject private var tray: DeletionTray
    let category: ScanCategory
    @State private var showReviewed = false
    @State private var showApproveAll = false

    private var all: [PhotoReviewGroup] { model.groups(in: category) }
    private var pending: [PhotoReviewGroup] { all.filter { !tray.reviewedGroupIDs.contains($0.id) } }
    private var visible: [PhotoReviewGroup] { showReviewed ? all : pending }

    /// Exact groups whose copies the safety policy allows to pre-mark.
    private var approvable: [PhotoReviewGroup] {
        guard category == .exact else { return [] }
        return pending.filter { !SafetyPolicy.evaluate($0.coreCluster).preselected.isEmpty }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.s + Spacing.xs) {
                if !approvable.isEmpty { approveAllButton }
                if visible.isEmpty { emptyState }
                ForEach(visible) { group in
                    NavigationLink {
                        ReviewGroupView(group: group, tray: tray)
                    } label: {
                        GroupRowView(group: group, status: status(group))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("group.\(group.id)")
                }
            }
            .padding(Spacing.m)
        }
        .background(Color.surfaceBackground)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if all.count > pending.count {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle("Reviewed", isOn: $showReviewed).toggleStyle(.button)
                        .accessibilityIdentifier("inbox.reviewed")
                }
            }
        }
        .sheet(isPresented: $showApproveAll) {
            ApproveAllSheet(groups: approvable) { chosen in
                let items = chosen.map { group in
                    (group: group, selected: SafetyPolicy.evaluate(group.coreCluster).preselected)
                }
                tray.approveAll(items)
                HapticsService.shared.fire(.approve)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox.\(category.rawValue)")
    }

    private var approveAllButton: some View {
        let count = approvable.reduce(0) { $0 + SafetyPolicy.evaluate($1.coreCluster).preselected.count }
        let bytes = approvable.reduce(Int64(0)) { $0 + $1.estimatedVerifiedBytes }
        return Button { showApproveAll = true } label: {
            HStack {
                Image(systemName: "checkmark.circle")
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Approve all \(count) \(count == 1 ? "copy" : "copies")").appText(.groupTitle)
                    Text("\(bytes.friendlyBytes) verified · you'll see the list first").appText(.caption)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent).tint(Color.actionPrimary)
        .accessibilityIdentifier("inbox.approveall")
    }

    private func status(_ group: PhotoReviewGroup) -> String? {
        if tray.contains(group.id) { return "In your tray" }
        return tray.reviewedGroupIDs.contains(group.id) ? "Skipped" : nil
    }

    @ViewBuilder private var emptyState: some View {
        if model.isScanning {
            ContentStateView<Int, EmptyView>(state: .loading(progress: model.progress, message: "Still looking. Groups appear here as they're found.")) { _ in EmptyView() }
        } else if model.phase == .finished {
            ContentStateView<Int, EmptyView>(state: .empty(title: all.isEmpty ? "Nothing found" : "All reviewed",
                message: all.isEmpty ? "Nothing in this category turned up in the \(model.statistics.photosEnumerated.formatted()) photos checked. That doesn't prove there's nothing more."
                                     : "You've been through every group here.")) { _ in EmptyView() }
        } else {
            ContentStateView<Int, EmptyView>(state: .empty(title: "No groups yet", message: "Scan your photos from the home screen to fill this list.")) { _ in EmptyView() }
        }
    }
}

struct GroupRowView: View {
    let group: PhotoReviewGroup
    var status: String?
    var body: some View {
        HStack(spacing: Spacing.m) {
            PhotoThumbnailView(assetID: group.keeper.id, target: 160)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: Radius.photo))
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("\(group.all.count) photos").appText(.groupTitle).foregroundStyle(Color.textPrimary)
                Text(group.estimatedVerifiedBytes > 0 ? "\(group.estimatedVerifiedBytes.friendlyBytes) verified" : "Size not verified")
                    .appText(.secondary).foregroundStyle(Color.textSecondary)
                if let status {
                    Text(status).appText(.chip).foregroundStyle(Color.actionPrimary)
                } else if group.kind == .similar {
                    Text("You choose what to remove").appText(.caption).foregroundStyle(Color.warningAccent)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Color.textSecondary).accessibilityHidden(true)
        }
        .padding(Spacing.s + Spacing.xs)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.m))
        .accessibilityElement(children: .combine)
    }
}
