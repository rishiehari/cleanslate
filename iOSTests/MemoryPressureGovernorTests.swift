import XCTest
import UIKit
@testable import CleanSlate

/// F03.7: memory pressure shapes the governor — warning shrinks batches and drops caches;
/// critical (or < 100 MB) pauses up to 60 s, then stops with progress saved.
@MainActor
final class MemoryPressureGovernorTests: XCTestCase {
    /// Sendable counter for closures that the compiler cannot prove are isolated.
    final class Counter: @unchecked Sendable { var value = 0 }
    final class PressureBox: @unchecked Sendable { var value = MemoryPressure.normal }
    private func governor(pressure: MemoryPressure, memoryBytes: Int = 1_000_000_000,
                          maximumPauseSeconds: Int = 600) -> ResourceGovernor {
        ResourceGovernor(inputs: .init(thermalState: { .nominal }, availableMemoryBytes: { memoryBytes },
                                       lowPowerMode: { false }, memoryPressure: { pressure }, sleep: { _ in }),
                         cores: 8, maximumPauseSeconds: maximumPauseSeconds)
    }

    func testWarningShrinksBatchAndDropsCachesOncePerEpisode() async {
        let governor = governor(pressure: .warning)
        let drops = Counter()
        governor.dropCachesRequested = { drops.value += 1 }
        _ = await governor.checkpoint()
        XCTAssertEqual(governor.batchSize, 25, "base 100 / 4 under .warning")
        _ = await governor.checkpoint()
        XCTAssertEqual(drops.value, 1, "caches are dropped once per pressure episode, not per checkpoint")
        let decision = await governor.checkpoint()
        XCTAssertEqual(decision, .proceed(concurrency: 1), "warning narrows the width to 1")
    }

    func testCriticalPausesThenStopsWithSavedProgress() async {
        // The pause loop sleeps in 2 s steps; after the 60 s budget it stops (30 sleeps).
        let sleeps = Counter()
        let governor = ResourceGovernor(inputs: .init(thermalState: { .nominal }, availableMemoryBytes: { 1_000_000_000 },
                                                      lowPowerMode: { false }, memoryPressure: { .critical },
                                                      sleep: { _ in sleeps.value += 1 }),
                                        cores: 8, maximumPauseSeconds: 600)
        let decision = await governor.checkpoint()
        XCTAssertEqual(sleeps.value, 30, "paused in 2 s steps for the full 60 s budget")
        if case .stop(let reason) = decision {
            XCTAssertEqual(reason, "Paused to free memory. Your progress is saved.")
        } else {
            XCTFail("expected .stop after the memory pause budget, got \(decision)")
        }
    }

    func testUnder100MBAvailableAlsoPauses() async throws {
        // The <100 MB memory floor is real-device only (the simulator's probe is unreliable);
        // on the simulator this case cannot occur, so skip instead of pretending.
        #if targetEnvironment(simulator)
        throw XCTSkip("os_proc_available_memory() is unreliable on the simulator; device-only path")
        #else
        let sleeps = Counter()
        let governor = ResourceGovernor(inputs: .init(thermalState: { .nominal }, availableMemoryBytes: { 90 * 1024 * 1024 },
                                                      lowPowerMode: { false }, memoryPressure: { .normal },
                                                      sleep: { _ in sleeps.value += 1 }),
                                        cores: 8, maximumPauseSeconds: 600)
        _ = await governor.checkpoint()
        XCTAssertGreaterThan(sleeps.value, 0, "< 100 MB available pauses even at .normal pressure")
        #endif
    }

    func testExistingLowMemoryBehaviorIsUnchanged() async {
        // < 150 MB (but >= 100 MB) keeps the old width-1 proceed, no pause.
        let sleeps = Counter()
        let governor = ResourceGovernor(inputs: .init(thermalState: { .nominal }, availableMemoryBytes: { 120 * 1024 * 1024 },
                                                      lowPowerMode: { false }, memoryPressure: { .normal },
                                                      sleep: { _ in sleeps.value += 1 }),
                                        cores: 8, maximumPauseSeconds: 600)
        let decision = await governor.checkpoint()
        XCTAssertEqual(decision, .proceed(concurrency: 1))
        XCTAssertEqual(sleeps.value, 0, "the legacy <150 MB path still proceeds immediately")
        XCTAssertEqual(governor.batchSize, 100)
    }

    func testWarningDropCachesReachesTheEngineCaches() async throws {
        let pressure = PressureBox()
        let governor = ResourceGovernor(inputs: .init(thermalState: { .nominal }, availableMemoryBytes: { 1_000_000_000 },
                                                      lowPowerMode: { false }, memoryPressure: { pressure.value }, sleep: { _ in }),
                                        cores: 8, maximumPauseSeconds: 600)
        let library = FakePhotoLibrary()
        let spec = FakePhotoLibrary.RenderSpec(base: 31)
        library.add("dc-a", content: "a", at: 1_000_000, spec: spec)
        library.add("dc-b", content: "b", at: 9_000_000, spec: spec)
        let model = try ScanTestRig.model(library: library, governor: governor)
        await model.runScan()
        XCTAssertGreaterThan(model.debugEngineCacheCounts.quality, 0, "the scan filled the quality cache")
        pressure.value = .warning
        _ = await governor.checkpoint()
        XCTAssertEqual(model.debugEngineCacheCounts.prints, 0, "dropCachesRequested cleared the print cache")
        XCTAssertEqual(model.debugEngineCacheCounts.quality, 0, "dropCachesRequested cleared the quality cache")
        XCTAssertEqual(governor.batchSize, 25)
    }

    func testEngineEffectiveWidthIsOneAtFair() async {
        // The governor may publish width 2 at .fair; ScanLimits clamps the engine to 1.
        let governor = ResourceGovernor(inputs: .init(thermalState: { .fair }, availableMemoryBytes: { 1_000_000_000 },
                                                      lowPowerMode: { false }, memoryPressure: { .normal }, sleep: { _ in }),
                                        cores: 8, maximumPauseSeconds: 600)
        if case .proceed(let width) = await governor.checkpoint() {
            XCTAssertEqual(width, 2, "governor still publishes its thermal width")
        } else {
            XCTFail("expected .proceed at .fair")
        }
        XCTAssertEqual(ScanLimits().maxInFlight, 1, "the engine clamps every tier to one asset in flight")
    }

    func testMonitorDecaysToNormalAfterThirtySeconds() {
        let clock = TestClock2()
        let monitor = MemoryPressureMonitor(now: { clock.now })
        monitor.start()
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertEqual(monitor.currentLevel, .warning)
        clock.now.addTimeInterval(29)
        XCTAssertEqual(monitor.currentLevel, .warning, "still within the decay window")
        clock.now.addTimeInterval(2)
        XCTAssertEqual(monitor.currentLevel, .normal, "decays to .normal 30 s after the last event")
    }
}

private final class TestClock2: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000)
}
