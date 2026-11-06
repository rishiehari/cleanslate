import SwiftUI

/// Plain-words reasons behind a suggestion (U5). Tapping opens an explanation.
enum Evidence: String, CaseIterable, Identifiable {
    case identicalFile, sameBurst, looksSimilar, inICloud
    case differentPeople, differentText
    var id: String { rawValue }

    var title: String {
        switch self {
        case .identicalFile: "Identical file"
        case .sameBurst: "Same burst"
        case .looksSimilar: "Looks similar"
        case .inICloud: "In iCloud"
        case .differentPeople: "Different people"
        case .differentText: "Different text"
        }
    }

    var symbol: String {
        switch self {
        case .identicalFile: "checkmark.seal"
        case .sameBurst: "square.stack.3d.down.right"
        case .looksSimilar: "eye"
        case .inICloud: "icloud"
        case .differentPeople: "person.2"
        case .differentText: "textformat"
        }
    }

    var isWarning: Bool { self == .differentPeople || self == .differentText }

    var explanation: String {
        switch self {
        case .identicalFile: "Every file in these photos is byte-for-byte the same. Nothing is lost by keeping one."
        case .sameBurst: "These were taken together in one burst. Look for the best moment before you remove any."
        case .looksSimilar: "These look alike to the computer. That doesn't mean one is a copy of the other, so you pick what to remove."
        case .inICloud: "The full photo is in iCloud and wasn't checked. Turn on iCloud verification to compare the originals."
        case .differentPeople: "The number of faces differs between these photos. The one you remove may be the only shot of someone."
        case .differentText: "The text in these photos differs. A sign, screen or note may only appear in one."
        }
    }
}

struct EvidenceChip: View {
    let evidence: Evidence
    var action: (() -> Void)?

    var body: some View {
        Button { action?() } label: {
            Label(evidence.title, systemImage: evidence.symbol)
                .appText(.chip)
                .padding(.horizontal, Spacing.s + Spacing.xs)
                .padding(.vertical, Spacing.xs + Spacing.xxs)
                .foregroundStyle(evidence.isWarning ? Color.warningAccent : Color.textPrimary)
                .background((evidence.isWarning ? Color.warningAccent : Color.protectedAccent).opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows why")
        .accessibilityIdentifier("chip.\(evidence.rawValue)")
    }
}

#Preview("Chips") {
    VStack(alignment: .leading, spacing: Spacing.s) {
        ForEach(Evidence.allCases) { EvidenceChip(evidence: $0) }
    }
    .padding(Spacing.m)
}
