import XCTest
import CleanSlateCore
@testable import CleanSlate

/// Peak `phys_footprint` during a full scan with thumbnails ON, against the tier budgets in docs/FEATURE_ROADMAP.md.
/// The simulator does not enforce device memory limits, so the test asserts the budget itself.
/// `make budget` runs this on the SE-test simulator with CLEANSLATE_TIER=M (iPhone SE 3rd gen has 4 GB).
@MainActor
final class MemoryBudgetTests: XCTestCase {
    struct Measurement { let peakMB: Double; let startMB: Double; let seconds: Double; let groups: Int; let photos: Int }

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
        print("BUDGET tier=\(BudgetTier.current.rawValue) scope=\(label) photos=\(photos) peakMB=\(String(format: "%.1f", peak)) startMB=\(String(format: "%.1f", start)) seconds=\(String(format: "%.1f", seconds)) groups=\(model.groups.count)")
        return Measurement(peakMB: peak, startMB: start, seconds: seconds, groups: model.groups.count, photos: photos)
    }

    func testFootprintAtScope100AndScope10000() async throws {
        let budget = BudgetTier.current.peakBudgetMB
        let small = try await measureScan(photos: 100, label: "100")
        let large = try await measureScan(photos: 10_000, label: "10000")
        let growth = large.peakMB - small.peakMB
        print("BUDGET growth100to10000MB=\(String(format: "%.1f", growth)) budgetMB=\(budget)")
        XCTAssertGreaterThan(small.groups, 0)
        XCTAssertGreaterThan(large.groups, 0)
        XCTAssertLessThanOrEqual(small.peakMB, budget, "scope 100 peak footprint")
        XCTAssertLessThanOrEqual(large.peakMB, budget, "scope 10,000 peak footprint")
        // The flat-footprint target (growth <= 15 MB) is delivered by F03's bounded engine. F01 records the baseline;
        // F03 deletes this expectation and the assert becomes a plain one.
        XCTExpectFailure("fixed by F03: footprint is not yet flat from 100 to 10,000 photos", options: .nonStrict()) {
            XCTAssertLessThanOrEqual(growth, 15, "growth from scope 100 to 10,000 was \(growth) MB")
        }
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
