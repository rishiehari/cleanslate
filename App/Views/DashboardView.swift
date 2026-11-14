import SwiftUI
import Photos

struct DashboardView: View {
    @EnvironmentObject private var model: CleaningViewModel
    @EnvironmentObject private var tray: DeletionTray
    @EnvironmentObject private var labels: LabelStore
    @EnvironmentObject private var trustState: TrustState
    @AppStorage("onboarding.seen.v1") private var onboardingSeen = false
    @AppStorage(HapticsService.defaultsKey) private var hapticsOn = true
    @State private var showClearCache = false
    @State private var showTray = false
    @State private var showVerifySheet = false
    @State private var showHistory = false
    @State private var showDiagnostics = false
    @State private var showPrivacyView = false
    @State private var showDataOnPhoneView = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    if needsPermission {
                        permissionCard
                    } else {
                        // Show scan progress card while scanning
                        if model.isScanning {
                            ScanProgressCard(snapshot: model.progressSnapshot)
                                .accessibilityIdentifier("scan.progress")
                        } else {
                            ScanStatusCard(snapshot: model.progressSnapshot)
                        }
                        PhotoActivityCard()
                        if model.potentialVerifiedBytes > 0 { StorageHero(verifiedBytes: model.potentialVerifiedBytes) }
                        if model.authorization == .limited {
                            Label("You gave CleanSlate access to some photos. It can only look at those.", systemImage: "exclamationmark.circle")
                                .appText(.caption).foregroundStyle(Color.warningAccent)
                        }
                        categories
                    }
                    thingsToKnow
                }
                .padding(Spacing.m)
                .frame(maxWidth: AdaptiveLayout.readableContentWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollEdgeEffectHidden(true, for: .bottom)
            .background(Color.surfaceBackground)
            .task(id: model.authorization.rawValue) { await model.loadActivityOverview() }
            .navigationTitle("CleanSlate")
            .navigationDestination(isPresented: $showDiagnostics) { DiagnosticsView() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    TrayButton(count: tray.photoCount) { showTray = true }
                }
                ToolbarItem(placement: .topBarTrailing) { menu }
            }
            .fullScreenCover(isPresented: Binding(get: { !onboardingSeen }, set: { if !$0 { onboardingSeen = true } })) {
                OnboardingView { onboardingSeen = true }
            }
            .sheet(isPresented: $showTray) { TrayView(tray: tray) }
            .sheet(isPresented: $showVerifySheet) { VerifyICloudSheet(policy: model.networkPolicy) }
            .sheet(isPresented: $showHistory) { NavigationStack { HistoryView().toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { showHistory = false } } } } }
            .sheet(isPresented: $showPrivacyView) { PrivacyView() }
            .sheet(isPresented: $showDataOnPhoneView) { 
                NavigationStack {
                    DataOnPhoneView(inventory: LocalDataInventory(model: model, diagnostics: model.diagnostics, activity: nil))
                }
            }
            .alert("Clear local index?", isPresented: $showClearCache) {
                Button("Cancel", role: .cancel) {}
                Button("Clear index", role: .destructive) { model.clearIndex() }
            } message: {
                Text("Removes CleanSlate's saved scan data. Your photos aren't touched.")
            }
        }
    }

    private var needsPermission: Bool {
        [.notDetermined, .denied, .restricted].contains(model.authorization)
    }

    private var menu: some View {
        Menu {
            Toggle("Haptics", systemImage: "iphone.radiowaves.left.and.right", isOn: $hapticsOn)
            Button("History", systemImage: "clock.arrow.circlepath") { showHistory = true }
            Button("Diagnostics", systemImage: "stethoscope") { showDiagnostics = true }
                .accessibilityIdentifier("menu.diagnostics")
            Button("iCloud originals…", systemImage: "icloud.and.arrow.down") { showVerifySheet = true }
            Button("Your privacy", systemImage: "lock.shield") { showPrivacyView = true }
            Button("Data on this iPhone", systemImage: "iphone") { showDataOnPhoneView = true }
            Button("Show intro again", systemImage: "questionmark.circle") { onboardingSeen = false }
            if labels.corrections > 0 {
                Label("Suggestions you corrected: \(labels.corrections)", systemImage: "hand.thumbsdown")
            }
            if LabelStore.isAvailableInThisBuild {
                Toggle("Label mode (testers)", systemImage: "tag", isOn: $labels.isEnabled)
                if labels.isEnabled, let url = try? labels.exportFile() {
                    ShareLink("Export labels (anonymous)", item: url)
                }
            }
            Button("Open Photos settings", systemImage: "hand.raised") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Clear saved scan data", systemImage: "trash.slash") { showClearCache = true }
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("dashboard.menu")
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label("Your photos stay yours", systemImage: "lock.shield").appText(.groupTitle)
            Text("To find copies, CleanSlate needs to look at your photos. It all happens on this device, and nothing is deleted without your say-so.")
                .appText(.body).foregroundStyle(Color.textSecondary)
            Button("Allow Photos access") { model.requestPermission() }
                .buttonStyle(.glassProminent).tint(Color.actionPrimary)
                .disabled(model.authorization == .restricted)
                .accessibilityIdentifier("permission.allow")
            if model.authorization == .denied {
                Text("Photos access is off. Turn it on in Settings to continue.")
                    .appText(.caption).foregroundStyle(Color.textSecondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("permission.card")
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: Spacing.s + Spacing.xs) {
            Text("What to review").appText(.title).foregroundStyle(Color.textPrimary)
            ForEach(visibleCategories) { category in
                if category.isAvailable {
                    NavigationLink {
                        if category.standaloneKind != nil { StandaloneListView(category: category) }
                        else { CategoryGroupsView(category: category) }
                    } label: {
                        CategoryCardView(category: category, groupCount: model.count(in: category),
                                         verifiedBytes: model.verifiedBytes(in: category))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("category.\(category.rawValue)")
                } else {
                    CategoryCardView(category: category, groupCount: 0, verifiedBytes: 0)
                        .accessibilityIdentifier("category.\(category.rawValue)")
                }
            }
        }
    }

    private var visibleCategories: [ScanCategory] {
        ScanCategory.allCases.filter(\.isAvailable)
    }

    private var thingsToKnow: some View {
        DisclosureGroup("Things to know") {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Deleting with iCloud Photos on also removes the photo from your other devices. Recently Deleted keeps it for 30 days.")
                Text("File sizes shown are verified sizes. Actual free space can differ, especially with Optimize Storage.")
                Text("This version checks part of your library at a time, and can't compare photos that only live in iCloud. Similar shots are never selected for you.")
            }
            .appText(.caption).foregroundStyle(Color.textSecondary)
            .padding(.top, Spacing.s)
        }
        .appText(.secondary)
        .tint(Color.textSecondary)
        .accessibilityIdentifier("dashboard.thingstoknow")
    }

}
