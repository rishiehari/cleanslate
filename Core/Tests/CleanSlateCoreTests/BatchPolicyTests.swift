import XCTest
@testable import CleanSlateCore

final class BatchPolicyTests: XCTestCase {
    private func record(_ id: String, rev: String = "v1", flags: Set<PreservationFlag> = []) -> AssetRecord { AssetRecord(id: id, revision: rev, flags: flags) }
    private func exact(_ k: String, _ t: String) -> PairEvidence { PairEvidence(first: k, second: t, relation: .exactResources, completeResourceEquality: true) }
    private func plan(keep: String, delete: String) -> ApprovedDeletionPlan {
        var revisions = [keep: "v1"]; revisions[delete] = "v1"          // keep == delete is a legal (invalid) input in the fuzz
        return ApprovedDeletionPlan(selectedIDs: [delete], keeperIDs: [keep], expectedRevisions: revisions,
                                    wasExplicitlyConfirmedByUser: true, evidence: [exact(keep, delete)])
    }
    private func library(_ ids: [String]) -> [String: AssetRecord] { Dictionary(uniqueKeysWithValues: ids.map { ($0, record($0)) }) }

    func testAnEmptyBatchIsRejected() {
        XCTAssertFalse(SafetyPolicy.validateBatch([], currentByID: [:]).isValid)
    }

    func testIndependentValidPlansPass() {
        let result = SafetyPolicy.validateBatch([plan(keep: "a", delete: "b"), plan(keep: "c", delete: "d")], currentByID: library(["a", "b", "c", "d"]))
        XCTAssertTrue(result.isValid)
    }

    func testOneStalePlanPoisonsTheWholeBatchAndNamesIt() {
        var current = library(["a", "b", "c", "d"]); current["d"] = record("d", rev: "v2")
        let result = SafetyPolicy.validateBatch([plan(keep: "a", delete: "b"), plan(keep: "c", delete: "d")], currentByID: current)
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.planFailures, [1: .staleRevision])
    }

    func testAPhotoKeptInOneGroupCannotBeDeletedInAnother() {
        let result = SafetyPolicy.validateBatch([plan(keep: "a", delete: "b"), plan(keep: "c", delete: "a")], currentByID: library(["a", "b", "c"]))
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.batchFailure)
        XCTAssertEqual(Set(result.planFailures.keys), [0, 1], "both contradicting plans are named")
    }

    func testAPhotoCannotBeDeletedTwice() {
        let result = SafetyPolicy.validateBatch([plan(keep: "a", delete: "x"), plan(keep: "b", delete: "x")], currentByID: library(["a", "b", "x"]))
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.batchFailure)
    }

    func testBatchSizeLimit() {
        let ids = (0..<(SafetyPolicy.maximumBatchTargets + 1)).flatMap { ["k\($0)", "t\($0)"] }
        let plans = (0...SafetyPolicy.maximumBatchTargets).map { plan(keep: "k\($0)", delete: "t\($0)") }
        XCTAssertNotNil(SafetyPolicy.validateBatch(plans, currentByID: library(ids)).batchFailure)
        let ok = SafetyPolicy.validateBatch(Array(plans.prefix(SafetyPolicy.maximumBatchTargets)), currentByID: library(ids))
        XCTAssertTrue(ok.isValid, "exactly the limit is allowed")
    }

    func testProtectedTargetBlocksTheBatch() {
        var current = library(["a", "b", "c", "d"]); current["b"] = record("b", flags: [.favorite])
        let result = SafetyPolicy.validateBatch([plan(keep: "a", delete: "b"), plan(keep: "c", delete: "d")], currentByID: current)
        XCTAssertEqual(result.planFailures, [0: .protected])
    }

    /// Fuzz: for random batches that VALIDATE, no keeper is ever in the deletion set, no target repeats,
    /// and every target is individually valid.
    func testFuzzValidBatchesNeverDeleteAKeeperOrRepeatATarget() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<5_000 {
            let ids = (0..<12).map { "p\($0)" }
            var current = Dictionary(uniqueKeysWithValues: ids.map { ($0, record($0, flags: Int.random(in: 0..<6, using: &rng) == 0 ? [.favorite] : [])) })
            let plans: [ApprovedDeletionPlan] = (0..<Int.random(in: 1...5, using: &rng)).map { _ in
                let keep = ids.randomElement(using: &rng)!, del = ids.randomElement(using: &rng)!
                return plan(keep: keep, delete: del)
            }
            if Bool.random(using: &rng) { current[ids.randomElement(using: &rng)!] = nil }
            let result = SafetyPolicy.validateBatch(plans, currentByID: current)
            guard result.isValid else { continue }
            let deleted = plans.flatMap { Array($0.selectedIDs) }
            let kept = Set(plans.flatMap { Array($0.keeperIDs) })
            XCTAssertEqual(deleted.count, Set(deleted).count, "a target repeated")
            XCTAssertTrue(Set(deleted).isDisjoint(with: kept), "a keeper is also being deleted")
            for plan in plans { XCTAssertNil(SafetyPolicy.validateCommit(plan, currentByID: current)) }
        }
    }
}
