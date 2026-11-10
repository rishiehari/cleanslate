import SwiftUI
import UIKit

/// Settings → Diagnostics: a private, on-device record of how scans ran. Read-only except for
/// user-initiated share/delete. Content is plain words over numbers and counts (F02 allow-list).
struct DiagnosticsView: View {
    @State private var records: [DiagnosticRecord]
    @State private var shareURL: URL?
    @State private var showShareSheet = false
    @State private var showDeleteConfirmation = false
    private let log = DiagnosticsLog.shared

    init() {
        // Load synchronously so the first render is already in its final state (no empty→loaded flip);
        // the audit's elementDetection pass flags the transient render-server text that flip leaves behind.
        let records = DiagnosticsLog.shared.recent(limit: 10_000)
        _records = State(initialValue: records)
        _shareURL = State(initialValue: records.isEmpty ? nil : (try? DiagnosticsLog.shared.exportFile()))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("A private record of how scans ran on this iPhone. It never leaves your phone unless you share it.")
                    .appText(.secondary).foregroundStyle(Color.textSecondary)
                if records.isEmpty {
                    ContentStateView<Int, EmptyView>(state: .empty(title: "Nothing recorded yet",
                                                                   message: "After a scan, this shows how it went. It only ever holds timings and counts.")) { _ in
                        EmptyView()
                    }
                } else {
                    ContentStateView(state: .loaded(records)) { records in
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            summaryCard(DiagnosticsSummary(records: records))
                            details(Array(records.suffix(200)))
                        }
                    }
                }
                buttons
            }
            .padding(Spacing.m)
        }
        .background(Color.surfaceBackground)
        .scrollIndicators(.hidden)
        .navigationTitle("Diagnostics")
        .accessibilityIdentifier("diagnostics.screen")
        .task { reload() }
        .sheet(isPresented: $showShareSheet) {
            if let shareURL { ActivityShareSheet(url: shareURL) }
        }
        .alert("Delete diagnostics?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                try? log.deleteAll()
                reload()
            }
        } message: {
            Text("This removes the local record of how scans ran. Your photos and names were never in it.")
        }
    }

    // MARK: Summary

    private func summaryCard(_ summary: DiagnosticsSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            row("Last scan", value: lastScanText(summary))
            row("Stalls in the last 7 days", value: "\(summary.stallsLast7Days)")
            row("Slow moments", value: "\(summary.slowMoments)")
            row("Memory warnings", value: "\(summary.memoryWarnings)")
            row("Last unexpected stop", value: unexpectedStopText(summary))
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l))
        .accessibilityElement(children: .contain)     // one container; each row inside stays a single element
        .accessibilityIdentifier("diagnostics.summary")
    }

    /// Stacks vertically at large Dynamic Type (AX5) instead of truncating.
    private func row(_ title: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.s) {
                Text(title).appText(.body).foregroundStyle(Color.textSecondary)
                Spacer(minLength: Spacing.s)
                Text(value).appText(.body).foregroundStyle(Color.textPrimary)
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title).appText(.body).foregroundStyle(Color.textSecondary)
                Text(value).appText(.body).foregroundStyle(Color.textPrimary)
            }
        }
        .accessibilityElement(children: .combine)      // VoiceOver reads each row as one element
    }

    private func lastScanText(_ summary: DiagnosticsSummary) -> String {
        guard let outcome = summary.lastScanOutcome, let seconds = summary.lastScanSeconds else { return "Never" }
        let verb = outcome == .finished ? "Finished in" : "Stopped after"
        return "\(verb) \(DiagnosticEvent.duration(seconds * 1_000))"
    }

    private func unexpectedStopText(_ summary: DiagnosticsSummary) -> String {
        guard let date = summary.lastUnexpectedStop else { return "None" }
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        if days <= 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        return "\(days) days ago"
    }

    // MARK: Details

    private func details(_ events: [DiagnosticRecord]) -> some View {
        DisclosureGroup("Show details") {
            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(Array(events.enumerated()), id: \.offset) { _, record in
                    Text(record.event.summaryLine)
                        .appText(.secondary).foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .appText(.secondary)
        .tint(Color.textSecondary)
        .accessibilityIdentifier("diagnostics.details")
    }

    // MARK: Actions

    private var buttons: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if shareURL != nil {
                // A plain button rather than ShareLink: the audit's elementDetection pass flags
                // ShareLink's swizzled control with an unattributed "inaccessible text" finding.
                Button { showShareSheet = true } label: {
                    Label("Share diagnostics file", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("diagnostics.share")
                Text("Contains timings and counts only. No photos, names, dates or places.")
                    .appText(.caption).foregroundStyle(Color.textSecondary)
            }
            Button("Delete diagnostics", role: .destructive) { showDeleteConfirmation = true }
                .buttonStyle(.borderedProminent)
                .tint(Color.deleteAccent)
                .accessibilityIdentifier("diagnostics.delete")
                .disabled(records.isEmpty)
        }
    }

    private func reload() {
        records = log.recent(limit: 10_000)      // the rotation caps the log near 1 MB; this reads all of it
        shareURL = records.isEmpty ? nil : (try? log.exportFile())
    }
}

/// System share sheet for the exported `.jsonl`. The only way out of the app for the log.
private struct ActivityShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack { DiagnosticsView() }
}
