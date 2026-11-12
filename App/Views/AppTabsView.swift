import SwiftUI

/// Scene navigation stays independent of the system's tab/sidebar presentation.
enum AppDestination: String, Hashable {
    case home
    case swipeSave
}

/// Both review entrances share the same tray, undo history and deletion receipt.
struct AppTabsView: View {
    @EnvironmentObject private var model: CleaningViewModel
    @EnvironmentObject private var tray: DeletionTray
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var destination: AppDestination = .home

    var body: some View {
        TabView(selection: $destination) {
            Tab("Home", systemImage: "house", value: AppDestination.home) { DashboardView() }
            Tab("Swipe n Save", systemImage: "hand.draw", value: AppDestination.swipeSave) { SwipeSaveView() }
        }
        .tabViewStyle(.sidebarAdaptable)
        .overlay(alignment: .bottom) {
            if let toast = tray.toast {
                UndoToast(message: toast.message) { tray.undo(); HapticsService.shared.fire(.undo) }
                    .padding(.bottom, Spacing.barClearance * 2)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy, value: tray.toast)
        .fullScreenCover(isPresented: Binding(get: { tray.receipt != nil }, set: { if !$0 { tray.receipt = nil } })) {
            if let receipt = tray.receipt { ReceiptView(receipt: receipt) { tray.receipt = nil } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshPermissions() }
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            let library = model.library as? FakePhotoLibrary
            Color.clear.frame(width: 1, height: 1).accessibilityElement()
                .accessibilityIdentifier("debug.probe")
                .accessibilityValue("deleteCalls=\(library?.deleteCalls.count ?? -1);assets=\(library?.assets.count ?? -1);tray=\(tray.photoCount)")
        }
        #endif
    }
}
