import SwiftUI
import CleanSlateCore

/// Metadata hints guide the first scan; they never imply duplication or verified savings.
struct PhotoActivityCard: View {
    @EnvironmentObject private var model: CleaningViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label("Where to start", systemImage: "calendar").appText(.groupTitle)
            Text("Start with a busy week or a burst-heavy period. Check a small part of your library before going further.")
                .appText(.secondary).foregroundStyle(Color.textPrimary)
            if model.activityOverviewLoading {
                ProgressView("Reading photo activity…")
                Text("Dates and burst information only. No image analysis or downloads.")
                    .appText(.caption).foregroundStyle(Color.textPrimary)
            } else if let summary = model.activityOverview {
                Text("Activity in your latest \(summary.sampledCount.formatted()) accessible items\(summary.reachedLimit ? " (overview capped at 5,000)" : "").")
                    .appText(.caption).foregroundStyle(Color.textPrimary)
                if summary.periods.isEmpty {
                    Text("No dated photos found in this overview. Try Latest 100 or change the scan range below.")
                        .appText(.secondary)
                }
                if let first = summary.periods.first { periodRow(first, index: 0) }
                if summary.periods.count > 1 {
                    DisclosureGroup("More busy weeks") {
                        ForEach(Array(summary.periods.dropFirst().enumerated()), id: \.element.id) { index, period in
                            periodRow(period, index: index + 1)
                        }
                    }
                    .foregroundStyle(Color.textPrimary)
                }
                DisclosureGroup("About this overview") {
                    Text("Photo activity is a starting point, not a duplicate result. Each scan checks up to 2,000 items. Savings appear only after file sizes are verified.")
                        .appText(.caption).foregroundStyle(Color.textPrimary)
                }
                .foregroundStyle(Color.textPrimary)
            } else if let error = model.activityOverviewError {
                Text(error).appText(.secondary)
                Button("Try activity overview again") { Task { await model.loadActivityOverview() } }
                    .frame(minHeight: 44)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.m))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity.overview")
    }

    private func periodRow(_ period: PhotoActivityPeriod, index: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Week of \(period.start.formatted(date: .abbreviated, time: .omitted))").appText(.groupTitle)
            Text("\(period.itemCount.formatted()) items · \(period.burstPhotoCount.formatted()) burst photos in the overview")
                .appText(.secondary).foregroundStyle(Color.textPrimary)
            Button("Check this week", systemImage: "sparkle.magnifyingglass") { model.scan(period: period) }
                .buttonStyle(.bordered).tint(Color.textPrimary)
                .frame(minHeight: 44)
                .disabled(model.isScanning)
                .accessibilityIdentifier("activity.scan.\(index)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
