import SwiftUI
import CleanSlateCore

/// Everything the user told CleanSlate to never suggest. Reachable from Settings and from the tray when the rules can't be checked.
struct ProtectionRulesView: View {
    @EnvironmentObject private var model: CleaningViewModel

    var body: some View {
        Group {
            if let service = model.protectionService {
                ProtectionRulesContent(service: service)
            } else {
                ContentUnavailableView("Protected photos", systemImage: "lock.shield",
                                       description: Text("Protection rules aren't available in this build."))
            }
        }
        .navigationTitle("Protected photos")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.surfaceBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("protection.screen")
    }
}

private struct ProtectionRulesContent: View {
    @ObservedObject var service: ProtectionRuleService
    @EnvironmentObject private var model: CleaningViewModel
    @State private var pendingRemoval: ProtectionRule?
    @State private var confirmRemoveAll = false
    @State private var confirmContinue = false
    @State private var addingRange = false

    private var assetRules: [ProtectionRule] { service.rules.filter { if case .asset = $0.scope { true } else { false } } }
    private var dateRules: [ProtectionRule] { service.rules.filter { if case .dateRange = $0.scope { true } else { false } } }
    private var albumRules: [ProtectionRule] { service.rules.filter { if case .album = $0.scope { true } else { false } } }

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
            Button("Remove rule", role: .destructive) { Task { await service.remove(ruleID: rule.id) } }
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
                               ?? (snapshot == nil ? "Still protected. CleanSlate just can't see this photo at the moment." : "No date")) {
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
            Calendar.current.date(from: DateComponents(year: day.year, month: day.month, day: day.day))
                .map { $0.formatted(date: .abbreviated, time: .omitted) } ?? day.iso
        }
        let title = start == end ? format(start) : "\(format(start)) to \(format(end))"
        return AnyView(row(rule, title: title, subtitle: "Every photo taken on these days (\(zone))") {
            Image(systemName: "calendar").font(.title2).foregroundStyle(Color.actionPrimary)
                .frame(width: 56, height: 56).accessibilityHidden(true)
        })
    }

    private func row<Leading: View>(_ rule: ProtectionRule, title: String, subtitle: String,
                                    @ViewBuilder leading: () -> Leading) -> some View {
        HStack(spacing: Spacing.m) {
            leading()
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title).appText(.groupTitle).foregroundStyle(Color.textPrimary)
                Text(subtitle).appText(.secondary).foregroundStyle(Color.textSecondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Spacing.s)
            Button { pendingRemoval = rule } label: {
                Image(systemName: "minus.circle").frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Stop protecting")
            .accessibilityIdentifier("protection.rule.\(rule.id.uuidString).remove")
        }
        .swipeActions { Button("Remove", role: .destructive) { pendingRemoval = rule } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("protection.rule.\(rule.id.uuidString)")
    }
}
