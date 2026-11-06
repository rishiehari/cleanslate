import SwiftUI

/// The big "you can free X" number. Verified and estimated are shown separately (U10).
struct StorageHero: View {
    let verifiedBytes: Int64
    var estimatedBytes: Int64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("You can free up").appText(.secondary).foregroundStyle(Color.textSecondary)
            Text(verifiedBytes.friendlyBytes)
                .appText(.heroNumber)
                .foregroundStyle(Color.textPrimary)
                .contentTransition(.numericText(value: Double(verifiedBytes)))
                .animation(.snappy, value: verifiedBytes)
                .accessibilityIdentifier("hero.bytes")
            if estimatedBytes > 0 {
                Text("≈ \(estimatedBytes.friendlyBytes) more, estimated")
                    .appText(.caption).foregroundStyle(Color.textSecondary)
            }
            Text("Verified file sizes. Space on your iPhone and in iCloud is freed after you empty Recently Deleted.")
                .appText(.caption).foregroundStyle(Color.textSecondary)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Hero") {
    StorageHero(verifiedBytes: 3_100_000_000, estimatedBytes: 800_000_000).padding(Spacing.m)
        .background(Color.surfaceBackground)
}
