import SwiftUI

/// Compact scan status: plain words, determinate progress, always pausable (U11, U15).
struct ScanStatusCard: View {
    @EnvironmentObject private var model: CleaningViewModel

    @State private var choosingScope = false

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
                        .buttonStyle(AccessiblePrimaryButtonStyle())
                        .accessibilityIdentifier("dashboard.scan")
                }
            }
            Text("\(model.currentScanTitle) · up to \((model.currentScanScope.maximumItems ?? 2_000).formatted()) items")
                .appText(.caption).foregroundStyle(Color.textPrimary)
            if !model.isScanning {
                Button("Change scan range") { choosingScope = true }
                    .frame(minHeight: 44).accessibilityIdentifier("scan.changeScope")
            }
            if model.isScanning { ProgressView(value: model.progress) }
            if let detail { Text(detail).appText(.caption).foregroundStyle(Color.textPrimary) }
            if let message = model.statusMessage {
                Text(message).appText(.caption).foregroundStyle(Color.textPrimary)
            }
            if let pause = model.pauseReason {
                Label(pause, systemImage: "thermometer.medium").appText(.secondary).foregroundStyle(Color.warningAccent)
                    .accessibilityIdentifier("scan.pausereason")
            }
        }
        .padding(Spacing.m)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.m))
        .sheet(isPresented: $choosingScope) { ScanScopeView(isPresented: $choosingScope) }
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
        let checked = "\(s.photosEnumerated.formatted()) items in this scan"
        return s.cloudOnlyOrUnavailable > 0 ? "\(checked) · \(s.cloudOnlyOrUnavailable.formatted()) previews unavailable" : checked
    }
}
