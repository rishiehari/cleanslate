import Foundation
import BackgroundTasks

/// Lets a long scan keep going when the user leaves the app.
/// - iOS 26: a user-started "continued processing" task with system progress UI.
/// - Overnight: a processing task (only while charging) that catches up incrementally.
/// NOTE: the simulator does not support background processing; both paths need a device to verify.
@MainActor
enum BackgroundScanning {
    static let processingIdentifier = "org.cleanslate.free.scan"
    static let continuedWildcard = "org.cleanslate.free.continued.*"
    static let continuedIdentifier = "org.cleanslate.free.continued.scan"

    /// The scan the background tasks should drive. Set once at launch.
    static weak var model: CleaningViewModel?

    /// True once `register()` ran (the real app). Unit tests never register, so the BG submit
    /// stays inert there — BGTaskScheduler asserts on submissions without registration.
    static var didRegister = false
    /// What BGTaskScheduler actually accepted. `register` returns false when an identifier is not permitted
    /// or the runtime refuses it; submitting an unregistered request raises an ObjC assertion that aborts the
    /// app (found on a real-photo simulator run, 2026-11-12), so every submit is gated on these.
    static private(set) var processingRegistered = false
    static private(set) var continuedRegistered = false

    #if DEBUG
    /// Test seam: the simulator has no BG runtime; tests assert the request/registration logic instead.
    static var continuedProcessingRequestCount = 0
    #endif

    /// Registers handlers. Must be called before the app finishes launching.
    static func register() {
        didRegister = true
        processingRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: processingIdentifier, using: nil) { @Sendable task in
            guard let processing = task as? BGProcessingTask else { return }
            // BGTask is not Sendable, but its completion/expiration API is documented thread-safe; the launch
            // handler runs on a background queue, so it must not be main-actor isolated (runtime trap otherwise).
            nonisolated(unsafe) let task = processing
            let work = Task { @MainActor in
                guard let model else { task.setTaskCompleted(success: false); return }
                await model.runSelectedScan()
                task.setTaskCompleted(success: model.phase == .finished)
            }
            task.expirationHandler = { @Sendable in work.cancel() }   // bounded inventory restarts; revision-matched feature work can be reused
        }
        if #available(iOS 26.0, *) {
            continuedRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: continuedWildcard, using: nil) { @Sendable task in
                guard let continued = task as? BGContinuedProcessingTask else { return }
                nonisolated(unsafe) let task = continued   // see above
                let work = Task { @MainActor in
                    guard let model else { task.setTaskCompleted(success: false); return }
                    task.progress.totalUnitCount = 100
                    let reporter = Task { @MainActor in
                        while !Task.isCancelled {
                            task.progress.completedUnitCount = Int64(model.progress * 100)
                            task.updateTitle("Looking for copies", subtitle: model.phase.rawValue)
                            try? await Task.sleep(for: .seconds(1))
                        }
                    }
                    await model.runSelectedScan()
                    reporter.cancel()
                    task.setTaskCompleted(success: model.phase == .finished)
                }
                task.expirationHandler = { @Sendable in work.cancel() }
            }
        }
    }

    /// Asks the system to run an incremental catch-up scan while the phone is charging.
    static func scheduleOvernight() {
        let request = BGProcessingTaskRequest(identifier: processingIdentifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        guard processingRegistered else { return }
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Called when the user starts a scan, so it can continue after they leave the app (iOS 26+).
    static func requestContinuedProcessing() {
        #if DEBUG
        continuedProcessingRequestCount += 1
        #endif
        // Only the launched app submits: the unit-test host also runs init, and BGTaskScheduler
        // asserts on submits without a working registration (its plist entries are device-only).
        guard didRegister, continuedRegistered, NSClassFromString("XCTestCase") == nil else { return }
        guard #available(iOS 26.0, *) else { return }
        let request = BGContinuedProcessingTaskRequest(identifier: continuedIdentifier, title: "Looking for copies",
                                                       subtitle: "CleanSlate is scanning your photos on this device")
        request.strategy = .queue
        try? BGTaskScheduler.shared.submit(request)
    }
}
