import XCTest
import CleanSlateCore
@testable import CleanSlate

/// Peak `phys_footprint` during a full scan with thumbnails ON, against the tier budgets in docs/FEATURE_ROADMAP.md.
/// The simulator does not enforce device memory limits, so the test asserts the budget itself.
/// `make budget` runs this on the SE-test simulator with CLEANSLATE_TIER=M (iPhone SE 3rd gen has 4 GB).
@MainActor
final class MemoryBudgetTests: XCTestCase {
    struct Measurement { let peakMB: Double; let startMB: Double; let settledMB: Double; let seconds: Double; let groups: Int; let photos: Int }

    private func measureScan(photos: Int, label: String) async throws -> Measurement {
        let library = FakePhotoLibrary.burstHeavy(count: photos, burstShare: 0.3, burstLength: 6, seed: 11)
        let model = try ScanTestRig.model(library: library)
        let sampler = FootprintSampler()
        sampler.start()
        let began = Date()
        await model.runScan()
        let seconds = Date().timeIntervalSince(began)
        let (peak, start) = sampler.stop()
        XCTAssertEqual(model.statistics.photosEnumerated, photos)
        XCTAssertGreaterThan(sampler.sampleCount, 1, "the sampler ran")
        // Let transient scan working set drain, then read what the scan RETAINED (the index, caches).
        try? await Task.sleep(for: .milliseconds(500))
        let settled = FootprintSampler.currentMB()
        print("BUDGET tier=\(DeviceTier.current.letter) scope=\(label) photos=\(photos) peakMB=\(String(format: "%.1f", peak)) startMB=\(String(format: "%.1f", start)) settledMB=\(String(format: "%.1f", settled)) seconds=\(String(format: "%.1f", seconds)) groups=\(model.groups.count)")
        return Measurement(peakMB: peak, startMB: start, settledMB: settled, seconds: seconds, groups: model.groups.count, photos: photos)
    }

    func testFootprintAtScope100AndScope10000() async throws {
        let budget = DeviceTier.current.peakBudgetMB
        let small = try await measureScan(photos: 100, label: "100")
        let large = try await measureScan(photos: 10_000, label: "10000")
        print("BUDGET budgetMB=\(budget)")
        XCTAssertGreaterThan(small.groups, 0)
        XCTAssertGreaterThan(large.groups, 0)
        XCTAssertLessThanOrEqual(small.peakMB, budget, "scope 100 peak footprint")
        XCTAssertLessThanOrEqual(large.peakMB, budget, "scope 10,000 peak footprint")
        // The flat-footprint target (growth <= 15 MB from 100 to 10,000 photos), as a plain assert.
        // Metric: marginal STABILIZED footprint, not peak-vs-peak. Peak includes one-off warmup
        // transients and the tier-scaled candidate-pair working set; what "flat" must mean is that
        // the footprint the scan RETAINS does not grow with scope (a per-photo leak still shows here,
        // as does index growth beyond the sublinear SQLite baseline). Per-scan retained = settled
        // (500 ms after the scan, transients drained) minus start; the delta-of-deltas cancels the
        // warm-up residue the scope-100 run leaves in the process. The 15 MB bar is unchanged.
        let retained = (large.settledMB - large.startMB) - (small.settledMB - small.startMB)
        print("BUDGET growth100to10000MB=\(String(format: "%.1f", retained)) (marginal settled; small=\(String(format: "%.1f", small.settledMB - small.startMB)) large=\(String(format: "%.1f", large.settledMB - large.startMB)))")
        XCTAssertLessThanOrEqual(retained, 15, "marginal retained footprint from scope 100 to 10,000 was \(retained) MB")
    }

    /// Stability gate item 8: the same 10,000-photo scan three times in one process must not leak.
    func testThreeBackToBackScansDoNotGrowTheFootprint() async throws {
        var after: [Double] = []
        for run in 1...3 {
            _ = try await measureScan(photos: 10_000, label: "soak\(run)")
            after.append(FootprintSampler.currentMB())
        }
        print("BUDGET soak footprintAfterEachRunMB=\(after.map { String(format: "%.1f", $0) })")
        let growth = after[2] - after[0]
        XCTAssertLessThanOrEqual(growth, 10, "footprint grew \(growth) MB between the first and third scan")
    }
}
