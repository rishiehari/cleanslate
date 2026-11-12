import SwiftUI
import CleanSlateCore

/// Everything the user told CleanSlate to never suggest. Reachable from Settings and from the tray when the rules can't be checked.
struct ProtectionRulesView: View {
    @EnvironmentObject private var model: CleaningViewModel

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let service = model.protectionService {
                    ProtectionRulesContent(service: service, availableWidth: geometry.size.width)
                } else {
                    ContentUnavailableView("Protected photos", systemImage: "lock.shield",
                                           description: Text("Protection rules aren't available in this build."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Protected photos")
        .toolbar(UIDevice.current.userInterfaceIdiom == .phone ? .hidden : .automatic, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.surfaceBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("protection.screen")
    }
}

private struct ProtectionRulesContent: View {
    @ObservedObject var service: ProtectionRuleService
    let availableWidth: CGFloat
    @EnvironmentObject private var model: CleaningViewModel
    @State private var pendingRemoval: ProtectionRule?
    @State private var confirmRemoveAll = false
    @State private var confirmContinue = false
    @State private var addingRange = false
    @State private var query = ""
    @State private var searching = false
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Survives rotation, resizing and relaunch of the scene.
    @SceneStorage("protection.selectedRule") private var selectedRuleID = ""

    /// iPad-width windows get a list plus an inspector; compact windows and accessibility sizes push the detail instead.
    private var wide: Bool {
        AdaptiveLayout.showsProtectionInspector(width: availableWidth, accessibilityText: typeSize.isAccessibilitySize)
    }
    private var selectedRule: ProtectionRule? { service.rules.first { $0.id.uuidString == selectedRuleID } }

    private func matches(_ rule: ProtectionRule) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return true }
        return Self.searchText(for: rule).contains(text)
    }
    /// Rule type and date text only. Never a photo's content.
    private static func searchText(for rule: ProtectionRule) -> String {
        switch rule.scope {
        case .asset: return "photo"
        case .album: return "album"
        case .dateRange(let start, let end, let zone, _, _): return "dates date range \(start.iso) \(end.iso) \(zone)".lowercased()
        }
    }

    private var assetRules: [ProtectionRule] { service.rules.filter { if case .asset = $0.scope { matches($0) } else { false } } }
    private var dateRules: [ProtectionRule] { service.rules.filter { if case .dateRange = $0.scope { matches($0) } else { false } } }
    private var albumRules: [ProtectionRule] { service.rules.filter { if case .album = $0.scope { matches($0) } else { false } } }

    var body: some View {
        Group {
            switch service.availability {
            case .loading:
                VStack(spacing: Spacing.m) {
                    ProgressView()
                    Text("Loading your protected photos…").appText(.secondary).foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("protection.loading")
            case .unavailable:
                problem(title: "Your rules can't be read",
                        message: "CleanSlate can't read your protection rules right now, so it won't delete anything. Nothing was changed.",
                        id: "protection.unavailable") {
                    Button("Try again") { Task { await service.load() } }
                        .buttonStyle(.bordered).accessibilityIdentifier("protection.retry")
                }
            case .lost:
                problem(title: "Your rules may be missing",
                        message: "Your protection rules look older than expected, so some may be gone. CleanSlate won't delete anything until you decide.",
                        id: "protection.lost") {
                    Button("Continue without them") { confirmContinue = true }
                        .buttonStyle(.bordered).accessibilityIdentifier("protection.lost.continue")
                }
            case .ready:
                if service.rules.isEmpty { empty } else { list }
            }
        }
        .toolbar {
            if service.availability == .ready {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add dates", systemImage: "calendar.badge.plus") { addingRange = true }
                        .accessibilityIdentifier("protection.addRange")
                }
            }
            if (wide || !query.isEmpty || searching), !service.rules.isEmpty, service.availability == .ready {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Search", systemImage: "magnifyingglass") { searching = true }
                        .keyboardShortcut("f", modifiers: .command)
                        .accessibilityIdentifier("protection.search")
                }
            }
            if !service.rules.isEmpty, service.availability != .loading {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Remove all", systemImage: "trash", role: .destructive) { confirmRemoveAll = true }
                        .accessibilityIdentifier("protection.removeAll")
                }
            }
        }
        .sheet(isPresented: $addingRange) { ProtectSheet(assetIDs: [], preselected: [], startWithDates: true) }
        .confirmationDialog("Remove this rule?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                            titleVisibility: .visible, presenting: pendingRemoval) { rule in
            Button("Remove rule", role: .destructive) {
                if selectedRuleID == rule.id.uuidString { selectedRuleID = "" }
                Task { await service.remove(ruleID: rule.id) }
            }
                .accessibilityIdentifier("protection.remove.confirm")
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It may be suggested again after your next scan. Nothing is deleted.")
        }
        .confirmationDialog("Remove all rules?", isPresented: $confirmRemoveAll, titleVisibility: .visible) {
            Button("Remove all rules", role: .destructive) { Task { await service.removeAll() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything here may be suggested again after your next scan. Nothing is deleted.")
        }
        .confirmationDialog("Continue without your rules?", isPresented: $confirmContinue, titleVisibility: .visible) {
            Button("Continue without them", role: .destructive) { service.acknowledgeLost() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Photos you protected before may be suggested again. Nothing is deleted.")
        }
    }

    // MARK: States

    private var empty: some View {
        VStack(spacing: Spacing.m) {
            if model.authorization == .limited { limitedBanner }
            ContentUnavailableView {
                Label("Nothing protected yet", systemImage: "lock.shield").accessibilityIdentifier("protection.empty")
            } description: {
                Text("Choose \"Never suggest a photo…\" in a review to keep it out of every suggestion. Apple Photos isn't changed.")
            }
        }
    }

    private func problem<Actions: View>(title: String, message: String, id: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: Spacing.m) {
            ContentUnavailableView {
                Label(title, systemImage: "exclamationmark.shield").accessibilityIdentifier(id)
            } description: {
                Text(message)
            } actions: {
                actions()
                if !service.rules.isEmpty {
                    Button("Remove all rules", role: .destructive) { confirmRemoveAll = true }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var limitedBanner: some View {
        Label("Protected photos you haven't shared still stay protected.", systemImage: "info.circle")
            .appText(.secondary).foregroundStyle(Color.textPrimary)
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.m))
            .padding(.horizontal, Spacing.m)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("protection.limitedBanner")
    }

    private var list: some View {
        List {
            if model.authorization == .limited {
                Section { limitedBanner.listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
            }
            if !assetRules.isEmpty {
                Section {
                    sectionTitle("Photos", id: "protection.section.photos")
                    ForEach(assetRules) { rule in assetRow(rule) }
                }
            }
            if !dateRules.isEmpty {
                Section {
                    sectionTitle("Dates", id: "protection.section.dates")
                    ForEach(dateRules) { rule in dateRow(rule) }
                } footer: {
                    Text("Photos with no date are not covered by a date range.")
                }
            }
            if !albumRules.isEmpty {
                Section {
                    sectionTitle("Albums", id: "protection.section.albums")
                    ForEach(albumRules) { rule in
                        row(rule, title: "Album", subtitle: "Albums can't be shown here yet. Photos in any of your albums stay protected anyway.") {
                            Image(systemName: "rectangle.stack").accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollEdgeEffectHidden(true, for: .bottom)
        .modifier(RuleSearch(enabled: wide || !query.isEmpty || searching, query: $query, searching: $searching))
        // The setter ignores `false`: the system may collapse the inspector while rotating or resizing, and that must not
        // forget the selection. The inspector's own Close button clears it.
        .inspector(isPresented: Binding(get: { wide && selectedRule != nil }, set: { _ in })) {
            if let rule = selectedRule {
                ProtectionRuleDetail(rule: rule, wide: true, onClose: { selectedRuleID = "" }) { pendingRemoval = rule }
                    .inspectorColumnWidth(ideal: AdaptiveLayout.protectionInspectorWidth)
            }
        }
        .navigationDestination(isPresented: Binding(get: { !wide && selectedRule != nil }, set: { if !$0 && !wide { selectedRuleID = "" } })) {
            if let rule = selectedRule { ProtectionRuleDetail(rule: rule, wide: false, onClose: nil) { pendingRemoval = rule } }
        }
    }

    // MARK: Rows

    /// A title row instead of a system header, so its text sits on a token background the contrast audit can measure.
    private func sectionTitle(_ title: String, id: String) -> some View {
        Text(title).appText(.groupTitle).foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(id)
            .listRowBackground(Color.surfaceCard)
    }

    private func assetRow(_ rule: ProtectionRule) -> some View {
        guard case .asset(let id) = rule.scope else { return AnyView(EmptyView()) }
        let snapshot = model.library.snapshot(id: id, inspectAlbums: false)
        return AnyView(row(rule,
                           title: snapshot == nil ? "Not available right now" : "Photo",
                           subtitle: snapshot?.capturedAt.map { $0.formatted(date: .abbreviated, time: .omitted) }
                               ?? (snapshot == nil ? "Still protected." : "No date")) {
            if snapshot != nil {
                PhotoThumbnailView(assetID: id, target: 160)
                    .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: Radius.s))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "photo.badge.exclamationmark").font(.title2).foregroundStyle(Color.textSecondary)
                    .frame(width: 56, height: 56).accessibilityHidden(true)
            }
        })
    }

    private func dateRow(_ rule: ProtectionRule) -> some View {
        guard case .dateRange(let start, let end, let zone, _, _) = rule.scope else { return AnyView(EmptyView()) }
        func format(_ day: LocalDay) -> String {
            guard let interval = ProtectionDateResolver.interval(start: day, end: day, timeZoneID: zone),
                  let timeZone = TimeZone(identifier: zone) else { return day.iso }
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.timeZone = timeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: interval.start)
        }
        let title = start == end ? format(start) : "\(format(start)) to \(format(end))"
        return AnyView(row(rule, title: title, subtitle: "Every photo taken on these days (\(zone))") {
            Image(systemName: "calendar").font(.title2).foregroundStyle(Color.actionPrimary)
                .frame(width: 56, height: 56).accessibilityHidden(true)
        })
    }

    private func row<Leading: View>(_ rule: ProtectionRule, title: String, subtitle: String,
                                    @ViewBuilder leading: () -> Leading) -> some View {
        let details = VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title).appText(.groupTitle).foregroundStyle(Color.textPrimary)
            Text(subtitle).appText(.secondary).foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
        let remove = Button { pendingRemoval = rule } label: {
            Image(systemName: "minus.circle").frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Stop protecting")
        .accessibilityIdentifier("protection.rule.\(rule.id.uuidString).remove")
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    details
                    HStack {
                        leading()
                        Spacer(minLength: Spacing.s)
                        remove
                    }
                }
            } else {
                HStack(spacing: Spacing.m) {
                    leading()
                    details
                    Spacer(minLength: Spacing.s)
                    remove
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedRuleID = rule.id.uuidString }
        .listRowBackground(selectedRuleID == rule.id.uuidString ? Color.actionPrimary.opacity(0.18) : Color.surfaceCard)
        .swipeActions { Button("Remove", role: .destructive) { pendingRemoval = rule } }
        .accessibilityAddTraits(selectedRuleID == rule.id.uuidString ? .isSelected : [])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("protection.rule.\(rule.id.uuidString)")
    }
}

/// One rule in detail: what it covers and how to remove it. Shown in the iPad inspector or as a pushed screen.
private struct ProtectionRuleDetail: View {
    let rule: ProtectionRule
    let wide: Bool
    let onClose: (() -> Void)?
    let onRemove: () -> Void
    @EnvironmentObject private var model: CleaningViewModel
    @State private var coverage: Int?

    var body: some View {
        List {
            Section {
                Text(title).appText(.groupTitle).foregroundStyle(Color.textPrimary)
                Text(explanation).appText(.secondary).foregroundStyle(Color.textSecondary)
                if let coverage {
                    Text("\(coverage.formatted()) checked \(coverage == 1 ? "photo" : "photos") covered right now")
                        .appText(.secondary).foregroundStyle(Color.textSecondary)
                        .accessibilityIdentifier("protection.detail.coverage")
                }
            }
            Section {
                Button("Remove this rule", role: .destructive, action: onRemove)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("protection.detail.remove")
            } footer: {
                Text("It may be suggested again after your next scan. Nothing is deleted.")
            }
        }
        .navigationTitle(wide ? "" : "Rule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", action: onClose).accessibilityIdentifier("protection.inspector.close")
                }
            }
        }
        .task(id: rule.id) { await loadCoverage() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(wide ? "protection.inspector" : "protection.detail")
    }

    private var title: String {
        switch rule.scope {
        case .asset: "A photo"
        case .album: "An album"
        case .dateRange(let start, let end, _, _, _): start == end ? start.iso : "\(start.iso) to \(end.iso)"
        }
    }

    private var explanation: String {
        switch rule.scope {
        case .asset: "CleanSlate won't suggest deleting this photo. Apple Photos isn't changed."
        case .album: "Photos in this album stay protected."
        case .dateRange(_, _, let zone, _, _): "CleanSlate won't suggest deleting any photo taken on these days (\(zone))."
        }
    }

    private func loadCoverage() async {
        switch rule.scope {
        case .asset(let id): coverage = model.library.snapshot(id: id, inspectAlbums: false) == nil ? 0 : 1
        case .album: coverage = nil
        case .dateRange(_, _, _, let from, let to): coverage = await model.store.protectedRangeIndexedCount(start: from, end: to)
        }
    }
}

/// Search over rule types and dates, offered in wide windows only (a short phone list doesn't need it).
private struct RuleSearch: ViewModifier {
    let enabled: Bool
    @Binding var query: String
    @Binding var searching: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $query, isPresented: $searching, prompt: "Search rule types and dates")
        } else {
            content
        }
    }
}
