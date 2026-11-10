import XCTest
@testable import CleanSlate

final class DeviceTierTests: XCTestCase {
    private let gb: UInt64 = 1_073_741_824

    func testThresholdsFromPhysicalMemory() {
        XCTAssertEqual(DeviceTier.resolve(physicalMemory: 3 * gb), .low)            // iPhone 11 class
        XCTAssertEqual(DeviceTier.resolve(physicalMemory: 3_758_096_383), .low)
        XCTAssertEqual(DeviceTier.resolve(physicalMemory: 3_758_096_384), .mid)
        XCTAssertEqual(DeviceTier.resolve(physicalMemory: 4 * gb), .mid)            // iPhone SE 3
        XCTAssertEqual(DeviceTier.resolve(physicalMemory: 5_905_580_031), .mid)
        XCTAssertEqual(DeviceTier.resolve(physicalMemory: 5_905_580_032), .high)
        XCTAssertEqual(DeviceTier.resolve(physicalMemory: 12 * gb), .high)          // iPhone 17 Pro
    }

    func testEnvironmentOverrideWinsAndGarbageIsIgnored() {
        XCTAssertEqual(DeviceTier.resolve(physicalMemory: 12 * gb, environment: ["CLEANSLATE_TIER": "l"]), .low)
        XCTAssertEqual(DeviceTier.resolve(physicalMemory: 12 * gb, environment: ["CLEANSLATE_TIER": "M"]), .mid)
        XCTAssertEqual(DeviceTier.resolve(physicalMemory: 2 * gb, environment: ["CLEANSLATE_TIER": "H"]), .high)
        XCTAssertEqual(DeviceTier.resolve(physicalMemory: 2 * gb, environment: ["CLEANSLATE_TIER": "banana"]), .low)
    }

    /// Guards the budgets of docs/FEATURE_ROADMAP.md against silent loosening.
    func testBudgetsAreTheDocumentedOnes() {
        XCTAssertEqual(DeviceTier.low.peakBudgetMB, 120)
        XCTAssertEqual(DeviceTier.mid.peakBudgetMB, 160)
        XCTAssertEqual(DeviceTier.high.peakBudgetMB, 200)
        XCTAssertEqual([DeviceTier.low, .mid, .high].map(\.letter), ["L", "M", "H"])
    }

    func testMemoryProbeReportsThisProcess() {
        XCTAssertGreaterThan(MemoryProbe.footprintMB(), 5)
        XCTAssertLessThan(MemoryProbe.footprintMB(), 20_000)
        XCTAssertGreaterThanOrEqual(MemoryProbe.availableMB(), 0)        // the simulator may report 0
        XCTAssertEqual(MemoryProbe.footprintMB(), FootprintSampler.currentMB(), accuracy: 50)
    }
}
