import SwiftUI

/// The review inbox for one category.
struct CategoryGroupsView: View {
    @EnvironmentObject private var model: CleaningViewModel
    let category: ScanCategory

    private var groups: [PhotoReviewGroup] { model.groups(in: category) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if groups.isEmpty {
                    ContentUnavailableView(
                        model.phase == .finished ? "Nothing found yet" : "No groups yet",
                        systemImage: "checkmark.circle",
                        description: Text(model.phase == .finished
                            ? "Nothing in this category was confirmed in the part of your library we checked. That doesn't prove there's nothing there."
                            : "Scan your photos from the home screen to fill this list."))
                }
                ForEach(groups) { group in
                    NavigationLink {
                        ReviewGroupView(group: group)
                    } label: {
                        GroupRowView(group: group)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("group.\(group.id)")
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("inbox.\(category.rawValue)")
    }
}

struct GroupRowView: View {
    let group: PhotoReviewGroup
    var body: some View {
        HStack(spacing: 12) {
            PhotoThumbnailView(assetID: group.keeper.id, target: 160)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(group.candidates.count + 1) photos").font(.headline)
                Text(group.estimatedVerifiedBytes > 0
                     ? "\(group.estimatedVerifiedBytes.friendlyBytes) verified" : "Size not verified")
                    .font(.subheadline).foregroundStyle(.secondary)
                if group.kind == .similar {
                    Text("You choose what to remove").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
