import XCTest
@testable import CleanSlateCore

final class TrayConsistencyTests: XCTestCase {
    private func e(_ id: String, delete: Set<String>, keep: Set<String> = []) -> TrayConsistency.Entry {
        .init(id: id, targets: delete, keepers: keep)
    }

    func testDisjointEntriesHaveNoProblems() {
        XCTAssertTrue(TrayConsistency.problems([e("a", delete: ["a1"], keep: ["A"]), e("b", delete: ["b1"], keep: ["B"])], limit: 500).isEmpty)
    }

    func testSharedKeeperIsAllowed() {
        XCTAssertTrue(TrayConsistency.problems([e("a", delete: ["a1"], keep: ["K"]), e("b", delete: ["b1"], keep: ["K"])], limit: 500).isEmpty)
    }

    func testKeptInOneDeletedInAnotherFlagsBoth() {
        let p = TrayConsistency.problems([e("a", delete: ["c1"], keep: ["P"]), e("b", delete: ["P"], keep: ["Q"])], limit: 500)
        XCTAssertEqual(p, ["a": .overlapsAnotherEntry, "b": .overlapsAnotherEntry])
    }

    func testSameTargetTwiceFlagsBoth() {
        let p = TrayConsistency.problems([e("a", delete: ["T"], keep: ["A"]), e("b", delete: ["T"], keep: ["B"])], limit: 500)
        XCTAssertEqual(Set(p.keys), ["a", "b"])
    }

    func testKeeperlessStandaloneTargetingAGroupKeeperConflicts() {
        let p = TrayConsistency.problems([e("g", delete: ["c"], keep: ["K"]), e("s", delete: ["K"])], limit: 500)
        XCTAssertEqual(Set(p.keys), ["g", "s"])
    }

    func testTargetAndKeeperInsideOneEntryIsLeftToTheEntryPolicy() {
        XCTAssertTrue(TrayConsistency.problems([e("a", delete: ["X"], keep: ["X"])], limit: 500).isEmpty)
    }

    func testOversizeEntryIsTooLargeAndExactLimitIsFine() {
        let big = Set((0..<501).map { "x\($0)" }), exact = Set((0..<500).map { "y\($0)" })
        let p = TrayConsistency.problems([e("big", delete: big, keep: ["K"]), e("ok", delete: exact, keep: ["L"])], limit: 500)
        XCTAssertEqual(p, ["big": .tooLarge])
    }

    func testOverlapTakesPrecedenceOverTooLarge() {
        var big = Set((0..<501).map { "x\($0)" }); big.insert("P")
        let p = TrayConsistency.problems([e("big", delete: big, keep: ["K"]), e("other", delete: ["c"], keep: ["P"])], limit: 500)
        XCTAssertEqual(p["big"], .overlapsAnotherEntry)
    }

    func testEmptyTrayHasNoProblems() {
        XCTAssertTrue(TrayConsistency.problems([], limit: 500).isEmpty)
    }
}
