import SwiftUI

struct CategoryCardView: View {
    let category: ScanCategory
    let groupCount: Int
    let verifiedBytes: Int64

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: category.symbol)
                .font(.title2)
                .frame(width: IconSize.row + Spacing.s)
                .foregroundStyle(category.isAvailable ? Color.actionPrimary : Color.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(category.title).appText(.groupTitle)
                    .foregroundStyle(category.isAvailable ? Color.textPrimary : Color.textSecondary)
                Text(subtitle).appText(.secondary).foregroundStyle(Color.textSecondary)
            }
            Spacer()
            if category.isAvailable {
                Image(systemName: "chevron.right").foregroundStyle(Color.textSecondary).accessibilityHidden(true)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.m))
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        guard category.isAvailable else { return "Coming in a later build" }
        if groupCount == 0 { return category.summary }
        let groups = groupCount == 1 ? "1 group" : "\(groupCount) groups"
        return verifiedBytes > 0 ? "\(groups) · \(verifiedBytes.friendlyBytes) verified" : groups
    }
}

#Preview("Cards") {
    VStack(spacing: Spacing.s) {
        CategoryCardView(category: .exact, groupCount: 214, verifiedBytes: 3_100_000_000)
        CategoryCardView(category: .similar, groupCount: 0, verifiedBytes: 0)
        CategoryCardView(category: .videos, groupCount: 0, verifiedBytes: 0)
    }.padding(Spacing.m).background(Color.surfaceBackground)
}
