import XCTest
@testable import CleanSlateCore

final class StandalonePolicyTests: XCTestCase {
    private func record(_ id: String, rev: String = "v1", flags: Set<PreservationFlag> = []) -> AssetRecord {
        AssetRecord(id: id, revision: rev, flags: flags)
    }
    private func plan(_ ids: Set<String> = ["s1"], confirmed: Bool = true, individually: Set<String>? = nil,
                      revisions: [String: String]? = nil) -> StandaloneDeletionPlan {
        StandaloneDeletionPlan(selectedIDs: ids, expectedRevisions: revisions ?? Dictionary(uniqueKeysWithValues: ids.map { ($0, "v1") }),
                               individuallyConfirmedIDs: individually ?? ids, wasExplicitlyConfirmedByUser: confirmed)
    }

    func testValidPlanPasses() {
        XCTAssertNil(SafetyPolicy.validateStandalone(plan(["s1", "s2"]), currentByID: ["s1": record("s1"), "s2": record("s2")]))
    }
    func testRequiresExplicitConfirmation() {
        XCTAssertEqual(SafetyPolicy.validateStandalone(plan(confirmed: false), currentByID: ["s1": record("s1")]), .userConfirmationRequired)
    }
    func testEmptySelectionRejected() {
        XCTAssertEqual(SafetyPolicy.validateStandalone(plan([]), currentByID: [:]), .invalidSelection)
    }
    func testEveryItemMustBeIndividuallyConfirmed() {
        XCTAssertEqual(SafetyPolicy.validateStandalone(plan(["s1", "s2"], individually: ["s1"]),
                                                       currentByID: ["s1": record("s1"), "s2": record("s2")]), .invalidSelection)
    }
    func testStaleRevisionRejected() {
        XCTAssertEqual(SafetyPolicy.validateStandalone(plan(), currentByID: ["s1": record("s1", rev: "v2")]), .staleRevision)
    }
    func testMissingAssetRejected() {
        XCTAssertEqual(SafetyPolicy.validateStandalone(plan(), currentByID: [:]), .missingAsset)
        XCTAssertEqual(SafetyPolicy.validateStandalone(plan(revisions: [:]), currentByID: ["s1": record("s1")]), .missingAsset)
    }
    func testEmptyExpectedRevisionRejected() {
        XCTAssertEqual(SafetyPolicy.validateStandalone(plan(revisions: ["s1": ""]), currentByID: ["s1": record("s1", rev: "")]), .staleRevision)
    }
    func testEveryFlagBlocksBecauseThereIsNoKeeper() {
        for flag in PreservationFlag.allCases {
            XCTAssertEqual(SafetyPolicy.validateStandalone(plan(), currentByID: ["s1": record("s1", flags: [flag])]), .protected, "flag=\(flag)")
        }
    }
    func testOneBadItemBlocksTheWholePlan() {
        XCTAssertEqual(SafetyPolicy.validateStandalone(plan(["s1", "s2"]), currentByID: ["s1": record("s1"), "s2": record("s2", flags: [.favorite])]), .protected)
    }
    func testNewVideoFlagsAreClassifiedConditional() {
        XCTAssertTrue(PreservationFlag.conditional.contains(.cinematicVideo))
        XCTAssertTrue(PreservationFlag.conditional.contains(.spatialMedia))
    }
}
