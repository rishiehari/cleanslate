import XCTest
@testable import CleanSlateCore

final class SafetyPolicyTests: XCTestCase {
    private func photo(_ id: String, flags: Set<PreservationFlag> = [], revision: String = "v1") -> AssetRecord {
        AssetRecord(id: id, revision: revision, flags: flags)
    }
    private func exact(_ a: String = "a", _ b: String = "b") -> PairEvidence {
        PairEvidence(first: a, second: b, relation: .exactResources, completeResourceEquality: true)
    }
    private func cluster(_ target: AssetRecord = AssetRecord(id: "b", revision: "v1"),
                         evidence: [PairEvidence] = [PairEvidence(first: "a", second: "b", relation: .exactResources, completeResourceEquality: true)],
                         keepers: Set<String> = ["a"], suggestions: Set<String> = ["b"]) -> ReviewCluster {
        ReviewCluster(id: "g", assets: [photo("a"), target], keeperIDs: keepers,
                      suggestedRemovalIDs: suggestions, evidence: evidence)
    }
    func testExactPreselects() {
        let result = SafetyPolicy.evaluate(cluster())
        XCTAssertEqual(result.preselected, ["b"])
    }
    func testFullResourceVerificationRequired() {
        let result = SafetyPolicy.evaluate(cluster(evidence: [PairEvidence(first: "a", second: "b", relation: .exactResources)]))
        XCTAssertTrue(result.preselected.isEmpty)
        XCTAssertTrue(result.reviewOnly.contains("b"))
    }
    func testProtectionFlagsFailClosed() {
        for flag in PreservationFlag.allCases {
            let result = SafetyPolicy.evaluate(cluster(photo("b", flags: [flag])))
            XCTAssertEqual(result.blocked["b"], .protected, "flag=\(flag)")
        }
    }
    func testMissingKeeperBlocks() {
        XCTAssertEqual(SafetyPolicy.evaluate(cluster(keepers: [])).blocked["b"], .missingKeeper)
    }
    func testKeeperAlsoRemovedBlocks() {
        XCTAssertEqual(SafetyPolicy.evaluate(cluster(suggestions: ["a", "b"])).blocked["b"], .keeperAlsoRemoved)
    }
    func testTransitiveEvidenceCannotAuthorize() {
        XCTAssertEqual(SafetyPolicy.evaluate(cluster(evidence: [exact("b", "c")])).blocked["b"], .missingProof)
    }
    func testUniqueDifferenceBlocksEvenWithOtherExactLink() {
        let evidence = [exact(), PairEvidence(first: "a", second: "b", relation: .distinct, uniqueContentDetected: true)]
        XCTAssertEqual(SafetyPolicy.evaluate(cluster(evidence: evidence)).blocked["b"], .uniqueDifference)
    }
    func testNearDuplicatesReviewOnlyByDefault() {
        let e = PairEvidence(first: "a", second: "b", relation: .verifiedNearDuplicate, calibratedRedundancyProbability: 0.99999)
        XCTAssertEqual(SafetyPolicy.evaluate(cluster(evidence: [e])).reviewOnly, ["b"])
    }
    func testNearGateRequiresExplicitValidation() {
        let e = PairEvidence(first: "a", second: "b", relation: .verifiedNearDuplicate, calibratedRedundancyProbability: 0.99999)
        XCTAssertEqual(SafetyPolicy.evaluate(cluster(evidence: [e]), configuration: .init(nearEnabled: true)).reviewOnly, ["b"])
        let enabled = SafetyPolicy.evaluate(cluster(evidence: [e]), configuration: .init(nearEnabled: true, independentSafetyGatePassed: true))
        XCTAssertEqual(enabled.preselected, ["b"])
    }
    func testInvalidProbabilityBlocks() {
        let e = PairEvidence(first: "a", second: "b", relation: .verifiedNearDuplicate, calibratedRedundancyProbability: .nan)
        XCTAssertEqual(SafetyPolicy.evaluate(cluster(evidence: [e])).blocked["b"], .invalidConfidence)
    }
    func testApprovalRequired() {
        let plan = ApprovedDeletionPlan(selectedIDs: ["b"], keeperIDs: ["a"], expectedRevisions: ["a":"v1", "b":"v1"], wasExplicitlyConfirmedByUser: false, evidence: [exact()])
        XCTAssertEqual(SafetyPolicy.validateCommit(plan, currentByID: ["a":photo("a"),"b":photo("b")]), .userConfirmationRequired)
    }
    func testCommitRejectsStaleAsset() {
        let plan = ApprovedDeletionPlan(selectedIDs: ["b"], keeperIDs: ["a"], expectedRevisions: ["a":"v1", "b":"v1"], wasExplicitlyConfirmedByUser: true, evidence: [exact()])
        XCTAssertEqual(SafetyPolicy.validateCommit(plan, currentByID: ["a":photo("a"),"b":photo("b",revision:"v2")]), .staleRevision)
    }
    func testCommitRejectsMissingKeeper() {
        let plan = ApprovedDeletionPlan(selectedIDs: ["b"], keeperIDs: ["a"], expectedRevisions: ["a":"v1", "b":"v1"], wasExplicitlyConfirmedByUser: true, evidence: [exact()])
        XCTAssertEqual(SafetyPolicy.validateCommit(plan, currentByID: ["b":photo("b")]), .missingAsset)
    }
    func testCommitAcceptsValidReviewedPlan() {
        let plan = ApprovedDeletionPlan(selectedIDs: ["b"], keeperIDs: ["a"], expectedRevisions: ["a":"v1", "b":"v1"], wasExplicitlyConfirmedByUser: true, evidence: [exact()])
        XCTAssertNil(SafetyPolicy.validateCommit(plan, currentByID: ["a":photo("a"),"b":photo("b")]))
    }
    func testCommitRejectsNoProofDespiteConfirmation() {
        let plan = ApprovedDeletionPlan(selectedIDs: ["b"], keeperIDs: ["a"], expectedRevisions: ["a":"v1", "b":"v1"], wasExplicitlyConfirmedByUser: true, evidence: [])
        XCTAssertEqual(SafetyPolicy.validateCommit(plan, currentByID: ["a":photo("a"),"b":photo("b")]), .missingProof)
    }
    func testCommitRequiresManualReviewForNearMatch() {
        let near = PairEvidence(first: "a", second: "b", relation: .verifiedNearDuplicate, calibratedRedundancyProbability: 0.9999)
        let base = ApprovedDeletionPlan(selectedIDs: ["b"], keeperIDs: ["a"], expectedRevisions: ["a":"v1", "b":"v1"], wasExplicitlyConfirmedByUser: true, evidence: [near])
        XCTAssertEqual(SafetyPolicy.validateCommit(base, currentByID: ["a":photo("a"),"b":photo("b")]), .invalidSelection)
        let manuallyReviewed = ApprovedDeletionPlan(selectedIDs: ["b"], keeperIDs: ["a"], expectedRevisions: ["a":"v1", "b":"v1"], wasExplicitlyConfirmedByUser: true, evidence: [near], manuallyReviewedIDs: ["b"])
        XCTAssertNil(SafetyPolicy.validateCommit(manuallyReviewed, currentByID: ["a":photo("a"),"b":photo("b")]))
    }
    func testCommitRejectsProtected() {
        let plan = ApprovedDeletionPlan(selectedIDs: ["b"], keeperIDs: ["a"], expectedRevisions: ["a":"v1", "b":"v1"], wasExplicitlyConfirmedByUser: true, evidence: [exact()])
        XCTAssertEqual(SafetyPolicy.validateCommit(plan, currentByID: ["a":photo("a"),"b":photo("b",flags:[.raw])]), .protected)
    }
    func testGroupRejectsTransitiveChain() {
        let groups = ConservativeGrouping.groups(assetIDs: ["a","b","c"], edges: [exact("a","b"),exact("b","c")])
        XCTAssertEqual(groups, [["a","b"]])
    }
    func testCompleteCliqueGroups() {
        let groups = ConservativeGrouping.groups(assetIDs: ["a","b","c"], edges: [exact("a","b"),exact("b","c"),exact("a","c")])
        XCTAssertEqual(groups, [["a","b","c"]])
    }
    func testSafetyBoundZeroFailures() {
        let upper = SafetyStatistics.oneSidedUpperBound(failures: 0, trials: 3000)!
        XCTAssertEqual(upper, 0.00099808, accuracy: 0.0000001)
    }
    func testSafetyBoundSingleFailureHigher() {
        let upper = SafetyStatistics.oneSidedUpperBound(failures: 1, trials: 3000)!
        XCTAssertGreaterThan(upper, 0.001)
    }
    func testInvalidStatistics() {
        XCTAssertNil(SafetyStatistics.oneSidedUpperBound(failures: -1, trials: 100))
        XCTAssertNil(SafetyStatistics.oneSidedUpperBound(failures: 0, trials: 0))
    }
}
