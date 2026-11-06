import SwiftUI

struct CategoryCardView: View {
    let category: ScanCategory
    let groupCount: Int
    let verifiedBytes: Int64

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: category.symbol)
                .font(.title2)
                .frame(width: 40)
                .foregroundStyle(category.isAvailable ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(category.title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if category.isAvailable {
                Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .opacity(category.isAvailable ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        guard category.isAvailable else { return "Coming in a later build" }
        if groupCount == 0 { return category.summary }
        let groups = groupCount == 1 ? "1 group" : "\(groupCount) groups"
        return verifiedBytes > 0 ? "\(groups) · \(verifiedBytes.friendlyBytes) verified" : groups
    }
}
