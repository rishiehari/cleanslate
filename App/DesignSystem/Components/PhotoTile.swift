import SwiftUI

/// A photo with a decision badge. Content layer: NO glass (U7).
struct PhotoTile: View {
    let assetID: String
    var decision: Decision?
    var target: CGFloat = 600
    var caption: String?

    var body: some View {
        PhotoThumbnailView(assetID: assetID, target: target)
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Radius.photo))
            .overlay(RoundedRectangle(cornerRadius: Radius.photo).strokeBorder(borderColor, lineWidth: borderWidth))
            .overlay(alignment: .topLeading) {
                if let decision { DecisionBadge(decision: decision).padding(Spacing.s) }
            }
            .overlay(alignment: .bottomTrailing) {
                if let caption {
                    Text(caption).appText(.badge).foregroundStyle(.white)
                        .padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xs)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(Spacing.s)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.photo))
    }

    private var borderWidth: CGFloat { decision == nil || decision == .undecided ? 0 : 3 }
    private var borderColor: Color {
        switch decision {
        case .keep: .keepAccent
        case .delete: .deleteAccent
        default: .clear
        }
    }
}
