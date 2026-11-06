import SwiftUI

/// Toolbar button showing how many photos are approved and waiting (U8).
struct TrayButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: count > 0 ? "tray.full.fill" : "tray")
                .symbolEffect(.bounce, value: count)
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text("\(count)")
                            .appText(.badge)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Spacing.xs + Spacing.xxs)
                            .background(Color.deleteAccent, in: Capsule())
                            .contentTransition(.numericText(value: Double(count)))
                            .animation(.snappy, value: count)
                            .offset(x: Spacing.s, y: -Spacing.s)
                    }
                }
        }
        .accessibilityLabel(count == 0 ? "Deletion tray, empty" : "Deletion tray, \(count) photos ready to delete")
        .accessibilityIdentifier("tray.button")
    }
}

#Preview("Tray") {
    HStack(spacing: Spacing.l) { TrayButton(count: 0) {}; TrayButton(count: 14) {} }.padding(Spacing.l)
}
