import XCTest
@testable import CleanSlate

/// Per-tier scan bounds (docs/features/F03 sub-task 2).
@MainActor
final class ScanLimitsTests: XCTestCase {
    func testTierCaps() {
        let low = ScanLimits(tier: .low), mid = ScanLimits(tier: .mid), high = ScanLimits(tier: .high)
        for limits in [low, mid, high] {
            XCTAssertEqual(limits.maxInFlight, 1, "strictly one asset in flight on every tier")
            XCTAssertEqual(limits.inventoryPage, 1_000, "paging pinned by existing tests")
            XCTAssertEqual(limits.featurePage, 200)
            XCTAssertEqual(limits.fingerprintSide, 128)
            XCTAssertEqual(limits.momentBucketCap, 30)
        }
        XCTAssertEqual(low.visionSide, 256); XCTAssertEqual(low.candidatePairCap, 20_000)
        XCTAssertEqual(mid.visionSide, 320); XCTAssertEqual(mid.candidatePairCap, 40_000)
        XCTAssertEqual(high.visionSide, 384); XCTAssertEqual(high.candidatePairCap, 100_000)
    }

    func testVisionPairCapScalesWithScopeAndStopsAt30000() {
        let limits = ScanLimits(tier: .high)
        XCTAssertEqual(limits.visionPairCap(scopeCount: 100), 300)
        XCTAssertEqual(limits.visionPairCap(scopeCount: 7_000), 21_000)
        XCTAssertEqual(limits.visionPairCap(scopeCount: 1_000_000), 30_000)
        XCTAssertEqual(limits.visionPairCap(scopeCount: 0), 0)
    }

    func testFingerprintVersionIs2() {
        XCTAssertEqual(ScanEngine.featureVersion, 2, "128-px fingerprints are versioned away from v1 280-px hashes")
    }
}
