import SwiftUI
import Photos

struct DashboardView: View {
    @EnvironmentObject private var model: CleaningViewModel
    @EnvironmentObject private var tray: DeletionTray
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboarding.seen.v1") private var onboardingSeen = false
    @AppStorage(HapticsService.defaultsKey) private var hapticsOn = true
    @State private var showClearCache = false
    @State private var showTray = false
    @State private var showVerifySheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    if needsPermission {
                        permissionCard
                    } else {
                        StorageHero(verifiedBytes: model.potentialVerifiedBytes)
                        ScanStatusCard()
                        if model.authorization == .limited {
                            Label("You gave CleanSlate access to some photos. It can only look at those.", systemImage: "exclamationmark.circle")
                                .appText(.caption).foregroundStyle(Color.warningAccent)
                        }
                        categories
                    }
                    thingsToKnow
                }
                .padding(Spacing.m)
            }
            .background(Color.surfaceBackground)
            .navigationTitle("CleanSlate")
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
            .fullScreenCover(isPresented: Binding(get: { tray.receipt != nil }, set: { if !$0 { tray.receipt = nil } })) {
                if let receipt = tray.receipt { ReceiptView(receipt: receipt) { tray.receipt = nil } }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { model.refreshPermissions() }
            }
            .alert("Clear local index?", isPresented: $showClearCache) {
                Button("Cancel", role: .cancel) {}
                Button("Clear index", role: .destructive) { model.clearIndex() }
            } message: {
                Text("Removes CleanSlate's saved scan data. Your photos aren't touched.")
            }
        }
        // Outside the stack so they stay visible on pushed screens.
        .overlay(alignment: .bottom) {
            if let toast = tray.toast {
                UndoToast(message: toast.message) { tray.undo(); HapticsService.shared.fire(.undo) }
                    .padding(.bottom, Spacing.l + 56)   // clear of the approval bar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: tray.toast)
        #if DEBUG
        .overlay(alignment: .topLeading) { debugProbe }
        #endif
    }

    private var needsPermission: Bool {
        [.notDetermined, .denied, .restricted].contains(model.authorization)
    }

    private var menu: some View {
        Menu {
            Toggle("Haptics", systemImage: "iphone.radiowaves.left.and.right", isOn: $hapticsOn)
            Button("iCloud originals…", systemImage: "icloud.and.arrow.down") { showVerifySheet = true }
            Button("Show intro again", systemImage: "questionmark.circle") { onboardingSeen = false }
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
            Text("To find copies, CleanSlate needs to look at your photos. It all happens on this iPhone, and nothing is deleted without your say-so.")
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
                        CategoryGroupsView(category: category)
                    } label: {
                        CategoryCardView(category: category, groupCount: model.groups(in: category).count,
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
        #if DEBUG
        ScanCategory.allCases
        #else
        ScanCategory.allCases.filter(\.isAvailable)
        #endif
    }

    private var thingsToKnow: some View {
        DisclosureGroup("Things to know") {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Deleting with iCloud Photos on also removes the photo from your other devices. Recently Deleted keeps it for 30 days.")
                Text("File sizes shown are verified sizes. Actual free space can differ, especially with Optimize iPhone Storage.")
                Text("This version checks part of your library at a time, and can't compare photos that only live in iCloud. Similar shots are never selected for you.")
            }
            .appText(.caption).foregroundStyle(Color.textSecondary)
            .padding(.top, Spacing.s)
        }
        .appText(.secondary)
        .tint(Color.textSecondary)
        .accessibilityIdentifier("dashboard.thingstoknow")
    }

    #if DEBUG
    /// Lets UI tests assert how many delete requests reached the (fake) library.
    private var debugProbe: some View {
        let calls = (model.library as? FakePhotoLibrary)?.deleteCalls.count ?? -1
        let remaining = (model.library as? FakePhotoLibrary)?.assets.count ?? -1
        return Color.clear.frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier("debug.probe")
            .accessibilityValue("deleteCalls=\(calls);assets=\(remaining);tray=\(tray.photoCount)")
    }
    #endif
}
