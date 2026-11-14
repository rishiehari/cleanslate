import SwiftUI

/// Screenshots, screen recordings and large videos. There is no "keep one" photo here, so
/// NOTHING is selected for you: you tap what to delete (rule U4).
struct StandaloneListView: View {
    @EnvironmentObject private var model: CleaningViewModel
    @EnvironmentObject private var tray: DeletionTray
    @EnvironmentObject private var trustState: TrustState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    let category: ScanCategory

    @State private var selected: Set<String> = []
    @State private var olderThanThirtyDays = false
    @State private var notice: String?
    @State private var showHowDeletingSheet = false

    private var all: [StandaloneItem] { model.standalone(in: category) }
    private var items: [StandaloneItem] {
        guard olderThanThirtyDays else { return all }
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return all.filter { ($0.snapshot.capturedAt ?? .distantFuture) < cutoff }
    }
    /// Only what's visible counts: switching the filter can't leave hidden items selected.
    private var selectedItems: [StandaloneItem] { items.filter { selected.contains($0.id) } }
    private var selectedBytes: Int64 { selectedItems.reduce(Int64(0)) { $0 + ($1.verifiedBytes ?? 0) } }
    private var selectedEstimatedBytes: Int64 { selectedItems.reduce(Int64(0)) { $0 + ($1.verifiedBytes == nil ? ($1.estimatedBytes ?? 0) : 0) } }
    private var barSubtitle: String? {
        var parts: [String] = []
        if selectedBytes > 0 { parts.append(selectedBytes.friendlyBytes) }
        if selectedEstimatedBytes > 0 { parts.append("≈ \(selectedEstimatedBytes.friendlyBytes) est.") }
        return parts.isEmpty ? nil : parts.joined(separator: " + ")
    }
    private var isLargeFiles: Bool { category == .largeFiles }
    
    /// Preview gate: if user hasn't read how deleting works, show the preview bar
    private var shouldShowPreviewBar: Bool {
        !trustState.hasReadHowDeletingWorks && !selected.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text(isLargeFiles
                     ? "Your biggest videos, largest first. Tap the ones you want to delete."
                     : "Old screenshots and screen recordings. Tap the ones you want to delete.")
                    .appText(.secondary).foregroundStyle(Color.textSecondary)
                filters
                if let notice {
                    Label(notice, systemImage: "lock.fill").appText(.secondary).foregroundStyle(Color.textSecondary)
                        .padding(Spacing.s + Spacing.xs)
                        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.m))
                        .accessibilityIdentifier("standalone.notice")
                }
                if items.isEmpty { emptyState } else if isLargeFiles { list } else { grid }
                Text("Favorites, photos in your albums, and identical copies (see Exact copies and Videos) are left out. Nothing here is selected for you.")
                    .appText(.caption).foregroundStyle(Color.textSecondary)
            }
            .padding(Spacing.m)
            .padding(.bottom, Spacing.barClearance)
        }
        .scrollEdgeEffectHidden(true, for: .bottom)
        .background(Color.surfaceBackground)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // "Select all" is offered for screenshots only; big videos are always picked one by one.
            if !isLargeFiles || !selected.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selected.isEmpty ? "Select all" : "Clear") {
                        selected = selected.isEmpty ? Set(items.map(\.id)) : []     // protected/album items are already excluded; commit re-checks each one
                    }
                    .accessibilityIdentifier("standalone.selectall")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if shouldShowPreviewBar {
                ApprovalBar(approveTitle: "Ready to choose? See how deleting works",
                            subtitle: nil,
                            canApprove: true,
                            onSkip: { selected = [] },
                            onApprove: { showHowDeletingSheet = true })
                    .accessibilityIdentifier("approval.preview")
            } else {
                ApprovalBar(approveTitle: selected.isEmpty ? "Approve" : "Approve \(selected.count)",
                            subtitle: barSubtitle,
                            canApprove: !selected.isEmpty,
                            onSkip: { selected = [] },
                            onApprove: approve)
                    .accessibilityIdentifier("approval.approve")
            }
        }
        .sheet(isPresented: $showHowDeletingSheet) { 
            HowDeletingWorksSheet { 
                trustState.setHasReadHowDeletingWorks(true)
                // After reading, we can proceed with normal approval
                if !selected.isEmpty {
                    approve()
                }
            } 
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("standalone.\(category.rawValue)")
    }

    private var filters: some View {
        HStack {
            if !isLargeFiles {
                Button {
                    olderThanThirtyDays.toggle()
                } label: {
                    Label("Older than 30 days", systemImage: olderThanThirtyDays ? "checkmark.circle.fill" : "circle")
                        .appText(.chip)
                }
                .buttonStyle(.bordered)
                .tint(olderThanThirtyDays ? Color.actionPrimary : Color.textSecondary)
                .accessibilityValue(olderThanThirtyDays ? "On" : "Off")
                .accessibilityIdentifier("standalone.older")
            }
            Spacer()
            Text("\(items.count.formatted()) \(items.count == 1 ? "item" : "items")")
                .appText(.secondary).foregroundStyle(Color.textSecondary)
        }
    }

    private var grid: some View {
        let minimum = dynamicTypeSize.isAccessibilitySize
            ? AdaptiveLayout.accessibleTileWidth : AdaptiveLayout.minimumTileWidth
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: Spacing.xs)], spacing: Spacing.xs) {
            ForEach(items) { item in
                SelectableTile(item: item, isSelected: selected.contains(item.id)) { toggle(item) }
            }
        }
    }

    private var list: some View {
        LazyVStack(spacing: Spacing.s + Spacing.xs) {
            ForEach(items) { item in
                Button { toggle(item) } label: {
                    HStack(spacing: Spacing.m) {
                        SelectableTile(item: item, isSelected: selected.contains(item.id)) { toggle(item) }
                            .frame(width: 96, height: 72)
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(StandaloneFormat.size(item)).appText(.groupTitle).foregroundStyle(Color.textPrimary)
                            Text(StandaloneFormat.detail(item)).appText(.secondary).foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(Spacing.s + Spacing.xs)
                    .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.m))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(selected.contains(item.id) ? "Selected" : "Not selected"), \(StandaloneFormat.size(item)), \(StandaloneFormat.detail(item))")
                .accessibilityIdentifier("item.\(item.id)")
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        ContentStateView<Int, EmptyView>(state: .empty(
            title: model.phase == .finished ? "Nothing to show" : "Nothing yet",
            message: model.phase == .finished ? "Nothing here needs your attention in the part of your library we checked."
                                              : "Scan your photos from the home screen to fill this list.")) { _ in EmptyView() }
    }

    private func toggle(_ item: StandaloneItem) {
        if selected.contains(item.id) {
            selected.remove(item.id); notice = nil; HapticsService.shared.fire(.toggle)
        } else if let reason = model.selectionBlockReason(for: item) {
            notice = reason; HapticsService.shared.fire(.blocked)
        } else {
            selected.insert(item.id); notice = nil; HapticsService.shared.fire(.toggle)
            Task { await model.measureSize(of: item) }
        }
    }

    private func approve() {
        tray.approveStandalone(items: selectedItems)
        HapticsService.shared.fire(.approve)
        selected = []
    }
}

private struct SelectableTile: View {
    let item: StandaloneItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PhotoThumbnailView(assetID: item.id, target: 300, fill: true)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Radius.s))
                .overlay(RoundedRectangle(cornerRadius: Radius.s).strokeBorder(isSelected ? Color.deleteAccent : .clear, lineWidth: 3))
                .overlay(alignment: .topLeading) {
                    if isSelected { DecisionBadge(decision: .delete).padding(Spacing.xs) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if item.snapshot.isVideo {
                        Text(StandaloneFormat.duration(item.snapshot.durationSeconds)).appText(.badge).foregroundStyle(.white)
                            .padding(.horizontal, Spacing.xs + Spacing.xxs).padding(.vertical, Spacing.xxs)
                            .background(.black.opacity(0.78), in: Capsule()).padding(Spacing.xs)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isSelected ? "Selected for deletion" : "Not selected"), \(StandaloneFormat.detail(item))")
        .accessibilityIdentifier("tile.\(item.id)")
    }
}

enum StandaloneFormat {
    /// Verified sizes are plain; estimates carry "≈"; unknown sizes say where the file lives (U10).
    static func size(_ item: StandaloneItem) -> String {
        if let bytes = item.verifiedBytes { return bytes.friendlyBytes }
        if let estimate = item.estimatedBytes { return "≈ \(estimate.friendlyBytes) (estimated)" }
        return "Size in iCloud"
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
                             : String(format: "%d:%02d", total / 60, total % 60)
    }

    static func detail(_ item: StandaloneItem) -> String {
        var parts: [String] = []
        if item.snapshot.isScreenRecording { parts.append("Screen recording") }
        else if item.snapshot.isScreenshot { parts.append("Screenshot") }
        else if item.snapshot.isVideo { parts.append("Video") }
        if item.snapshot.isVideo { parts.append(duration(item.snapshot.durationSeconds)) }
        if let date = item.snapshot.capturedAt { parts.append(date.formatted(date: .abbreviated, time: .omitted)) }
        return parts.joined(separator: " · ")
    }
}
