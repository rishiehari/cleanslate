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
                         keepers: Set<String> = ["a"], suggestions: Set<String> = ["b"],
                         keeper: AssetRecord? = nil) -> ReviewCluster {
        ReviewCluster(id: "g", assets: [keeper ?? photo("a"), target], keeperIDs: keepers,
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
    // STEP 3.3 (owner review pending): the former testProtectionFlagsFailClosed looped over EVERY flag.
    // Flags are now classified; these tests keep the same fail-closed guarantee for hard flags and
    // pin down exactly when a conditional flag may be deleted.
    func testHardFlagsAlwaysBlock() {
        for flag in PreservationFlag.hard {
            let result = SafetyPolicy.evaluate(cluster(photo("b", flags: [flag]), keeper: photo("a", flags: [flag])))
            XCTAssertEqual(result.blocked["b"], .protected, "flag=\(flag)")
        }
    }
    func testConditionalFlagBlocksWithoutMatchingKeeper() {
        for flag in PreservationFlag.conditional {
            let result = SafetyPolicy.evaluate(cluster(photo("b", flags: [flag])))   // keeper has no flags
            XCTAssertEqual(result.blocked["b"], .protected, "flag=\(flag)")
        }
    }
    func testConditionalFlagBlocksWithoutCompleteEquality() {
        let e = PairEvidence(first: "a", second: "b", relation: .exactResources)  // equality not established
        let result = SafetyPolicy.evaluate(cluster(photo("b", flags: [.livePhoto]), evidence: [e], keeper: photo("a", flags: [.livePhoto])))
        XCTAssertTrue(result.preselected.isEmpty)
        XCTAssertEqual(result.blocked["b"], .protected)
    }
    func testConditionalFlagAllowedWithMatchingExactKeeper() {
        for flag in PreservationFlag.conditional {
            let result = SafetyPolicy.evaluate(cluster(photo("b", flags: [flag]), keeper: photo("a", flags: [flag])))
            XCTAssertEqual(result.preselected, ["b"], "flag=\(flag)")
        }
    }
    func testConditionalFlagNeverAllowedForNearDuplicate() {
        let e = PairEvidence(first: "a", second: "b", relation: .verifiedNearDuplicate, calibratedRedundancyProbability: 0.99999)
        let config = PreselectionConfiguration(nearEnabled: true, independentSafetyGatePassed: true)
        let result = SafetyPolicy.evaluate(cluster(photo("b", flags: [.livePhoto]), evidence: [e], keeper: photo("a", flags: [.livePhoto])),
                                           configuration: config)
        XCTAssertEqual(result.blocked["b"], .protected)
        XCTAssertTrue(result.preselected.isEmpty && result.reviewOnly.isEmpty)
    }
    func testKeeperMustCarryAllConditionalFlagsOfTarget() {
        let result = SafetyPolicy.evaluate(cluster(photo("b", flags: [.livePhoto, .edited]), keeper: photo("a", flags: [.livePhoto])))
        XCTAssertEqual(result.blocked["b"], .protected)
    }
    func testAllFlagsAreClassifiedExactlyOnce() {
        XCTAssertEqual(PreservationFlag.hard.union(PreservationFlag.conditional), Set(PreservationFlag.allCases))
        XCTAssertTrue(PreservationFlag.hard.isDisjoint(with: PreservationFlag.conditional))
    }
    func testCommitRejectsHardFlagButAllowsMatchingConditional() {
        let plan = ApprovedDeletionPlan(selectedIDs: ["b"], keeperIDs: ["a"], expectedRevisions: ["a":"v1","b":"v1"],
                                        wasExplicitlyConfirmedByUser: true, evidence: [exact()])
        XCTAssertEqual(SafetyPolicy.validateCommit(plan, currentByID: ["a": photo("a"), "b": photo("b", flags: [.favorite])]), .protected)
        XCTAssertNil(SafetyPolicy.validateCommit(plan, currentByID: ["a": photo("a", flags: [.raw]), "b": photo("b", flags: [.raw])]))
        XCTAssertEqual(SafetyPolicy.validateCommit(plan, currentByID: ["a": photo("a"), "b": photo("b", flags: [.raw])]), .protected)
    }
    /// Fuzz: over random clusters, nothing with a hard flag is ever preselected, and a preselected
    /// conditional-flag target always has a directly linked, fully-equal keeper carrying its flags.
    func testFuzzInvariantsHoldOnRandomClusters() {
        var rng = SystemRandomNumberGenerator()
        let allFlags = PreservationFlag.allCases
        for _ in 0..<10_000 {
            func randomFlags() -> Set<PreservationFlag> { Set(allFlags.filter { _ in Int.random(in: 0..<4, using: &rng) == 0 }) }
            let keepers = ["k1", "k2"]
            let targets = (0..<3).map { "t\($0)" }
            var assets = keepers.map { photo($0, flags: randomFlags()) }
            assets += targets.map { photo($0, flags: randomFlags()) }
            var evidence: [PairEvidence] = []
            for t in targets { for k in keepers where Bool.random(using: &rng) {
                let relation: PairRelation = [.exactResources, .verifiedNearDuplicate, .visuallySimilar, .distinct, .uncertain].randomElement(using: &rng)!
                evidence.append(PairEvidence(first: k, second: t, relation: relation,
                    completeResourceEquality: Bool.random(using: &rng), uniqueContentDetected: Int.random(in: 0..<6, using: &rng) == 0,
                    calibratedRedundancyProbability: Bool.random(using: &rng) ? Double.random(in: 0...1, using: &rng) : nil))
            }}
            let c = ReviewCluster(id: "f", assets: assets, keeperIDs: Set(keepers), suggestedRemovalIDs: Set(targets), evidence: evidence)
            let config = PreselectionConfiguration(nearEnabled: Bool.random(using: &rng), independentSafetyGatePassed: Bool.random(using: &rng))
            let out = SafetyPolicy.evaluate(c, configuration: config)
            for id in out.preselected.union(out.reviewOnly) {
                let rec = assets.first { $0.id == id }!
                XCTAssertTrue(rec.flags.isDisjoint(with: PreservationFlag.hard), "hard flag leaked: \(rec.flags)")
                let cond = rec.flags.intersection(PreservationFlag.conditional)
                if !cond.isEmpty {
                    XCTAssertTrue(keepers.contains { k in
                        let kr = assets.first { $0.id == k }!
                        return cond.isSubset(of: kr.flags) && evidence.contains { $0.joins(id, k) && $0.relation == .exactResources && $0.completeResourceEquality }
                    }, "conditional target \(id) allowed without an equal keeper")
                }
            }
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

// N05 (append-only): the user-protection overlay flag is a hard block like any other.
extension SafetyPolicyTests {
    func testUserProtectedIsHard() {
        XCTAssertTrue(PreservationFlag.hard.contains(.userProtected))
        XCTAssertFalse(PreservationFlag.conditional.contains(.userProtected))
        let result = SafetyPolicy.evaluate(cluster(photo("b", flags: [.userProtected])))
        XCTAssertEqual(result.blocked["b"], .protected)
        XCTAssertTrue(result.preselected.isEmpty)
    }
    func testUserProtectedKeeperRemainsValidKeeper() {
        let result = SafetyPolicy.evaluate(cluster(keeper: photo("a", flags: [.userProtected])))
        XCTAssertEqual(result.preselected, ["b"])
        XCTAssertNil(result.blocked["a"])
    }
    func testUserProtectedTargetFailsCommit() {
        let plan = ApprovedDeletionPlan(selectedIDs: ["b"], keeperIDs: ["a"], expectedRevisions: ["a": "v1", "b": "v1"],
                                        wasExplicitlyConfirmedByUser: true, evidence: [exact()])
        XCTAssertEqual(SafetyPolicy.validateCommit(plan, currentByID: ["a": photo("a"), "b": photo("b", flags: [.userProtected])]), .protected)
        XCTAssertNil(SafetyPolicy.validateCommit(plan, currentByID: ["a": photo("a", flags: [.userProtected]), "b": photo("b")]))
    }
}
