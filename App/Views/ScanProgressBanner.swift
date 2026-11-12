import SwiftUI

/// One app-level scan remains visible while the user reviews results in either entrance.
struct ScanProgressBanner: View {
    @EnvironmentObject private var model: CleaningViewModel

    var body: some View {
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(model.phase.rawValue).appText(.secondary)
                ProgressView(value: model.progress)
                Text("\(model.statistics.photosEnumerated.formatted()) items · \(model.currentScanTitle)")
                    .appText(.caption).foregroundStyle(Color.textSecondary)
            }
            Button("Pause", systemImage: "pause.fill") { model.stop() }
                .frame(minHeight: 44).buttonStyle(.glass)
                .accessibilityIdentifier("scan.banner.pause")
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scan.banner")
    }
}
