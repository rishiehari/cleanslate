import SwiftUI

/// Always icon + word, so color is never the only signal (U2).
enum Decision: Equatable {
    case keep, delete, undecided
    case protected(reason: String)
}

struct DecisionBadge: View {
    let decision: Decision

    var body: some View {
        Label(title, systemImage: symbol)
        .appText(.chip)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .foregroundStyle(Color.onAccent)
        .background(tint, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch decision {
        case .keep: "Keep"
        case .delete: "Delete"
        case .undecided: "Tap to remove"
        case .protected: "Always kept"
        }
    }

    private var symbol: String {
        switch decision {
        case .keep: "checkmark.circle.fill"
        case .delete: "trash.circle.fill"
        case .undecided: "circle.dashed"
        case .protected: "lock.fill"
        }
    }

    private var tint: Color {
        switch decision {
        case .keep: .keepAccent
        case .delete: .deleteAccent
        case .undecided: .protectedAccent
        case .protected: .protectedAccent
        }
    }
}

#Preview("Badges") {
    VStack(alignment: .leading, spacing: Spacing.s) {
        DecisionBadge(decision: .keep)
        DecisionBadge(decision: .delete)
        DecisionBadge(decision: .undecided)
        DecisionBadge(decision: .protected(reason: "Favorite"))
    }
    .padding(Spacing.m)
}
