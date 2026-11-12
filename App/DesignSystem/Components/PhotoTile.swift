import SwiftUI
import CleanSlateCore

/// A photo with a decision badge. Content layer: NO glass (U7).
struct PhotoTile: View {
    let assetID: String
    var decision: Decision?
    var target: CGFloat = 600
    var caption: String?
    /// Live / edited / RAW shown as small symbols so users can see why a photo is special.
    var traits: Set<PreservationFlag> = []

    var body: some View {
        PhotoThumbnailView(assetID: assetID, target: target)
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Radius.photo))
            .overlay(RoundedRectangle(cornerRadius: Radius.photo).strokeBorder(borderColor, lineWidth: borderWidth))
            .overlay(alignment: .topLeading) {
                if let decision { DecisionBadge(decision: decision).padding(Spacing.s) }
            }
            .overlay(alignment: .topTrailing) {
                if let caption {
                    Text(caption).appText(.badge).foregroundStyle(.white)
                        .padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xs)
                        .background(.black.opacity(0.78), in: Capsule())
                        .padding(Spacing.s)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !traitSymbols.isEmpty {
                    HStack(spacing: Spacing.xs) {
                        ForEach(traitSymbols, id: \.symbol) { item in
                            Image(systemName: item.symbol).imageScale(.small).accessibilityLabel(item.label)
                        }
                    }
                    .foregroundStyle(.white).padding(Spacing.xs + Spacing.xxs)
                    .background(.black.opacity(0.78), in: Capsule()).padding(Spacing.s)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.photo))
    }

    private var traitSymbols: [(symbol: String, label: String)] {
        var items: [(String, String)] = []
        if traits.contains(.livePhoto) { items.append(("livephoto", "Live Photo")) }
        if traits.contains(.edited) { items.append(("slider.horizontal.3", "Edited")) }
        if traits.contains(.raw) { items.append(("camera.aperture", "RAW")) }
        if traits.contains(.userProtected) { items.append(("lock.shield.fill", "Protected by your rule")) }
        return items
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
