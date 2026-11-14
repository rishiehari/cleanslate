import XCTest
@testable import CleanSlateCore

final class StoragePlanTests: XCTestCase {
    
    func rec(_ id: String, _ bytes: Int64?, _ flags: Set<PreservationFlag> = []) -> AssetRecord {
        return AssetRecord(id: id, revision: "r-\(id)", flags: flags, verifiedLogicalBytes: bytes)
    }
    
    func goal(_ bytes: Int64) -> StorageGoal {
        return StorageGoal(id: UUID(), targetLogicalBytes: bytes, scopeID: "test-scope", createdAt: Date(timeIntervalSince1970: 0))
    }
    
    // MARK: - Tests from the task card
    
    func testInvalidTargetReturnsEmptyPlan() {
        let result = StoragePlanner.build(goal: goal(0), sources: [], maxItems: 10)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.unmetReason, .invalidTarget)
    }
    
    func testZeroMaxItemsIsInvalid() {
        let result = StoragePlanner.build(goal: goal(1000), sources: [], maxItems: 0)
        XCTAssertEqual(result.unmetReason, .invalidTarget)
    }
    
    func testExactGroupCountsOnlyTargetsNotKeeper() {
        let keeper = rec("K", 100, [])
        let target1 = rec("c1", 40, [])
        let target2 = rec("c2", 60, [])
        
        let source = PlanSource(id: "test-id", kind: .verifiedExact, keepers: [keeper], targets: [target1, target2])
        let result = StoragePlanner.build(goal: goal(1000), sources: [source], maxItems: 10)
        
        // The keeper (100 bytes) is not counted as a target, only the targets (40 + 60 = 100 bytes) are counted
        XCTAssertEqual(result.potentialKnownBytes, 100)
    }
    
    func testOverlappingAssetCountedOnce() {
        let assetX = rec("X", 500, [])
        
        // Create three sources that all reference the same asset X
        let exactSource = PlanSource(id: "exact", kind: .verifiedExact, keepers: [assetX], targets: [assetX])
        let screenshotSource = PlanSource(id: "screenshot", kind: .screenshots, keepers: [], targets: [assetX])
        let largeFileSource = PlanSource(id: "largeFile", kind: .largeFile, keepers: [], targets: [assetX])
        
        let result = StoragePlanner.build(goal: goal(1000 * 1024 * 1024), sources: [exactSource, screenshotSource, largeFileSource], maxItems: 10)
        
        // Asset X should only be counted once (in the first source - exact group)  
        XCTAssertEqual(result.potentialKnownBytes, 500)
        XCTAssertEqual(result.items.count, 1) // Only one item (the exact group)
        XCTAssertEqual(result.coverage.targetsSkippedDuplicate, 2) // Two duplicates skipped
    }
    
    func testProtectedTargetNeverCounted() {
        let protectedAsset = rec("P", 50, [.userProtected])
        
        let source = PlanSource(id: "test-id", kind: .largeFile, keepers: [], targets: [protectedAsset])
        let result = StoragePlanner.build(goal: goal(1000), sources: [source], maxItems: 10)
        
        // Protected asset should not appear in any items
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.coverage.targetsSkippedProtected, 1)
    }
    
    func testEveryHardFlagIsSkipped() {
        let flags = PreservationFlag.hard
        
        var sources: [PlanSource] = []
        for (index, flag) in flags.enumerated() {
            let asset = rec("asset-\(index)", 100, [flag])
            let source = PlanSource(id: "source-\(index)", kind: .largeFile, keepers: [], targets: [asset])
            sources.append(source)
        }
        
        let result = StoragePlanner.build(goal: goal(1000), sources: sources, maxItems: 10)
        
        // All protected assets should be skipped
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.coverage.targetsSkippedProtected, flags.count)
    }
    
    func testConditionalFlagIsNotSkippedByPlanner() {
        let asset = rec("asset", 50, [.livePhoto])
        
        let source = PlanSource(id: "test-id", kind: .largeFile, keepers: [], targets: [asset])
        let result = StoragePlanner.build(goal: goal(1000), sources: [source], maxItems: 10)
        
        // Conditional flag should not prevent counting
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].potentialBytes, 50)
    }
    
    func testKeeperOfAnotherSourceIsNeverATarget() {
        let keeperAsset = rec("P", 100, [])
        
        // First source: exact group with P as keeper (and also a target)
        let exactSource = PlanSource(id: "exact", kind: .verifiedExact, keepers: [keeperAsset], targets: [keeperAsset])
        
        // Second source: screenshot group that targets the same asset P 
        let screenshotSource = PlanSource(id: "screenshot", kind: .screenshots, keepers: [], targets: [keeperAsset])
        
        let result = StoragePlanner.build(goal: goal(1000), sources: [exactSource, screenshotSource], maxItems: 10)
        
        // The target P should be skipped because it's kept by the first source
        XCTAssertEqual(result.coverage.targetsSkippedKeptElsewhere, 1)
    }
    
    func testUnknownSizeIsUnknownNotZero() {
        let asset = rec("asset", nil, [])
        
        let source = PlanSource(id: "test-id", kind: .largeVideo, keepers: [], targets: [asset])
        let result = StoragePlanner.build(goal: goal(1000), sources: [source], maxItems: 10)
        
        // Should have nil potentialBytes and unknownSizeCount == 1
        XCTAssertEqual(result.items.count, 1)
        XCTAssertNil(result.items[0].potentialBytes)
        XCTAssertEqual(result.items[0].unknownSizeCount, 1)
        XCTAssertEqual(result.potentialKnownBytes, 0)
        XCTAssertEqual(result.coverage.unknownSizeTargets, 1)
    }
    
    func testMixedKnownAndUnknownSizes() {
        let asset1 = rec("asset1", 30, [])
        let asset2 = rec("asset2", nil, [])
        let asset3 = rec("asset3", 20, [])
        
        let source = PlanSource(id: "test-id", kind: .largeFile, keepers: [], targets: [asset1, asset2, asset3])
        let result = StoragePlanner.build(goal: goal(1000), sources: [source], maxItems: 10)
        
        // Should have potentialBytes == 50 (30 + 20) and unknownSizeCount == 1
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].potentialBytes, 50)
        XCTAssertEqual(result.items[0].unknownSizeCount, 1)
    }
    
    func testSimilarReviewNeverCountsTowardGoal() {
        let asset1 = rec("asset1", 100, [])
        let asset2 = rec("asset2", 200, [])
        
        let source = PlanSource(id: "test-id", kind: .similarReview, keepers: [], targets: [asset1, asset2])
        let result = StoragePlanner.build(goal: goal(1000), sources: [source], maxItems: 10)
        
        // Should have countsTowardGoal false and potentialBytes nil
        XCTAssertEqual(result.items.count, 1)
        XCTAssertFalse(result.items[0].countsTowardGoal)
        XCTAssertNil(result.items[0].potentialBytes)
        XCTAssertEqual(result.potentialKnownBytes, 0)
    }
    
    func testTierOrderThenBytesThenSizeThenID() {
        // This is a complex test that requires proper sorting
        // We'll create items with different tiers and sizes to verify ordering
        XCTFail("Not implemented yet")
    }
    
    func testStopsAfterItemThatCrossesTarget() {
        // Test with items of 60, 50, 40 bytes; goal 100 bytes
        // Should select first two items (60 + 50 = 110 >= 100)
        XCTFail("Not implemented yet")
    }
    
    func testUnmetWhenEvidenceShort() {
        // Test with items total 140 bytes; goal 500 bytes
        // Should be unmet because not enough evidence
        XCTFail("Not implemented yet")
    }
    
    func testUnmetWhenMaxItemsReached() {
        // Test with 5 items of 10 bytes each; goal 100 bytes; maxItems 2
        // Should select only 2 items and be unmet due to max items
        XCTFail("Not implemented yet")
    }
    
    func testTierCAppendedAfterCountingItemsWithinMaxItems() {
        // Test with 1 counting item (met goal) + 3 tier C items; maxItems 3
        // Should include counting item + 2 of the 3 tier C items (total 3)
        XCTFail("Not implemented yet")
    }
    
    func testInputOrderDoesNotChangeOutput() {
        // Test with shuffled sources to ensure deterministic ordering
        XCTFail("Not implemented yet")
    }
    
    func testEmptySourcesProduceNoItems() {
        let source = PlanSource(id: "test-id", kind: .verifiedExact, keepers: [], targets: [])
        let result = StoragePlanner.build(goal: goal(1000), sources: [source], maxItems: 10)
        
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.coverage.sourcesConsidered, 1)
    }
    
    func testExpectedRevisionsMatchRecords() {
        // Test that expectedRevisions matches records in items
        XCTFail("Not implemented yet")
    }
    
    func testLargeInputPerformance() {
        // Performance test with large input
        XCTFail("Not implemented yet")
    }
}