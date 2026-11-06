import SwiftUI

/// Compact scan status: plain words, determinate progress, always pausable (U11, U15).
struct ScanStatusCard: View {
    @EnvironmentObject private var model: CleaningViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s + Spacing.xs) {
            HStack {
                Text(headline).appText(.groupTitle).foregroundStyle(Color.textPrimary)
                Spacer()
                if model.isScanning {
                    Button("Pause", systemImage: "pause.fill") { model.stop() }
                        .buttonStyle(.glass).accessibilityIdentifier("dashboard.pause")
                } else {
                    Button(model.statistics.photosEnumerated > 0 ? "Scan again" : "Scan photos",
                           systemImage: "sparkle.magnifyingglass") { model.scan() }
                        .buttonStyle(.glassProminent).tint(Color.actionPrimary)
                        .accessibilityIdentifier("dashboard.scan")
                }
            }
            if model.isScanning { ProgressView(value: model.progress) }
            if let detail { Text(detail).appText(.caption).foregroundStyle(Color.textSecondary) }
            if let message = model.statusMessage {
                Text(message).appText(.caption).foregroundStyle(Color.textSecondary)
            }
            if model.statistics.truncated && !model.isScanning {
                Button("Look through more photos", systemImage: "plus.magnifyingglass") { model.scanMore() }
                    .appText(.secondary)
            }
        }
        .padding(Spacing.m)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.m))
    }

    private var headline: String {
        switch model.phase {
        case .idle: "Ready to look for copies"
        case .inventory: "Finding your photos"
        case .thumbnails: "Getting to know your photos"
        case .candidates: "Spotting possible copies"
        case .fullResources: "Checking the original files"
        case .sizing: "Measuring your videos and screenshots"
        case .vision: "Comparing similar shots"
        case .finished: "Scan finished"
        case .cancelled: "Scan paused"
        }
    }

    private var detail: String? {
        let s = model.statistics
        guard s.photosEnumerated > 0 else { return nil }
        let checked = "\(s.photosEnumerated.formatted()) photos checked"
        return s.cloudOnlyOrUnavailable > 0 ? "\(checked) · \(s.cloudOnlyOrUnavailable.formatted()) in iCloud weren't" : checked
    }
}
