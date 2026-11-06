import SwiftUI
import Photos

@main
struct CleanSlateApp: App {
    @StateObject private var model: CleaningViewModel
    private let library: PhotoLibraryClient

    init() {
        let environment = AppEnvironment.make()
        library = environment.library
        _model = StateObject(wrappedValue: environment.model)
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(model)
                .environmentObject(model.tray)
                .environment(\.photoLibrary, library)
                .tint(Color.actionPrimary)
        }
    }
}

/// Builds the real PhotoKit-backed model, or (DEBUG only) a deterministic fake for UI tests.
@MainActor
enum AppEnvironment {
    static func make() -> (model: CleaningViewModel, library: PhotoLibraryClient) {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        // Real writes (not argument-domain overrides) so the app can record onboarding as seen.
        if arguments.contains("-resetOnboarding") { UserDefaults.standard.set(false, forKey: "onboarding.seen.v1") }
        if arguments.contains("-skipOnboarding") { UserDefaults.standard.set(true, forKey: "onboarding.seen.v1") }
        if arguments.contains("-uiTestingFakeLibrary") {
            let auth = AuthArgument.current()
            let scenario = FakePhotoLibrary.uiTestScenario(authorization: auth)
            let trayURL = DeletionTray.defaultURL(name: "tray-uitest.json")
            if !arguments.contains("-keepTray"), let trayURL { try? FileManager.default.removeItem(at: trayURL) }
            let model = CleaningViewModel(library: scenario.library, tray: DeletionTray(fileURL: trayURL))
            if auth == .authorized { model.seedGroupsForUITesting(scenario.groups) }
            return (model, scenario.library)
        }
        #endif
        let library = PhotoKitLibraryClient.shared
        return (CleaningViewModel(library: library), library)
    }
}

#if DEBUG
private enum AuthArgument {
    /// `-uiTestingAuth denied|limited|authorized` (arrives through the argument domain of UserDefaults).
    static func current() -> PHAuthorizationStatus {
        switch UserDefaults.standard.string(forKey: "uiTestingAuth") {
        case "denied": .denied
        case "limited": .limited
        case "notDetermined": .notDetermined
        default: .authorized
        }
    }
}
#endif
