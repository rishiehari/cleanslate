import SwiftUI
import Photos

@main
struct CleanSlateApp: App {
    @StateObject private var model: CleaningViewModel
    private let library: PhotoLibraryClient
    private let watchdog: MainThreadWatchdog
    @StateObject private var labels = LabelStore(fileURL: LabelStore.defaultURL())

    init() {
        let environment = AppEnvironment.make()
        library = environment.library
        watchdog = environment.watchdog
        _model = StateObject(wrappedValue: environment.model)
        environment.watchdog.start()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let variant = Self.prototypeVariant {
                PrototypeHost(variant: variant)
            } else {
                root
            }
            #else
            root
            #endif
        }
    }

    #if DEBUG
    /// `-forceColorScheme dark|light` (design review; the simulator's own appearance switch is unreliable headless).
    private static var forcedScheme: ColorScheme? {
        switch UserDefaults.standard.string(forKey: "forceColorScheme") {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }

    /// `-prototype 1...5` shows a review-screen prototype instead of the app.
    private static var prototypeVariant: ReviewVariant? {
        let value = UserDefaults.standard.integer(forKey: "prototype")
        return ReviewVariant(rawValue: value)
    }
    #endif

    private var root: some View {
        Group {
            DashboardView()
                #if DEBUG
                .preferredColorScheme(Self.forcedScheme)
                #endif
                .environmentObject(model)
                .environmentObject(model.tray)
                .environmentObject(labels)
                .environment(\.photoLibraryOverride, library)
                .tint(Color.actionPrimary)
        }
    }
}

/// Builds the real PhotoKit-backed model, or (DEBUG only) a deterministic fake for UI tests.
@MainActor
enum AppEnvironment {
    struct Built {
        let model: CleaningViewModel
        let library: PhotoLibraryClient
        let watchdog: MainThreadWatchdog
    }

    static func make() -> Built {
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
            let suite = UserDefaults(suiteName: "org.cleanslate.uitest") ?? .standard
            suite.removePersistentDomain(forName: "org.cleanslate.uitest")
            let policy = NetworkPolicy(defaults: suite, pathCheck: { true })
            let model = CleaningViewModel(library: scenario.library, tray: DeletionTray(fileURL: trayURL), networkPolicy: policy,
                                          store: try? LibraryStore(path: nil))   // fake mode never touches the real index
            if auth == .authorized { model.seedGroupsForUITesting(scenario.groups, standalone: scenario.standalone) }
            let analyzer = FakePhotoAnalyzer()
            analyzer.descriptions = ["sim1-a": .init(faceCount: 2, text: ["market"]), "sim1-b": .init(faceCount: 3, text: ["market"]),
                                     "sim1-c": .init(faceCount: 2, text: ["market"])]       // sim1-b shows an extra person
            model.analyzer = analyzer
            return finish(model: model, library: scenario.library)
        }
        #endif
        let library = PhotoKitLibraryClient.shared
        return finish(model: CleaningViewModel(library: library), library: library)
    }

    /// Diagnostics owned by the process: the log lives on the model, the watchdog reads the live scan counters.
    private static func finish(model: CleaningViewModel, library: PhotoLibraryClient) -> Built {
        let log = model.diagnostics
        let counters = model.scanCounters
        let watchdog = MainThreadWatchdog(log: log, probes: .init(phase: { counters.snapshot.phase }))
        return Built(model: model, library: library, watchdog: watchdog)
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
