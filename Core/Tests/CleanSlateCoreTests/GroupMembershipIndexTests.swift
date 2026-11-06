import XCTest
@testable import CleanSlateCore

final class GroupMembershipIndexTests: XCTestCase {
    func testUnrelatedChangesAffectNothing() {
        let index = GroupMembershipIndex(groups: ["g1": ["a", "b"], "g2": ["c", "d"]])
        XCTAssertTrue(index.groupsAffected(by: ["x", "y"]).isEmpty)
    }

    func testOnlyGroupsContainingAChangedAssetAreAffected() {
        let index = GroupMembershipIndex(groups: ["g1": ["a", "b"], "g2": ["c", "d"], "g3": ["e", "f"]])
        XCTAssertEqual(index.groupsAffected(by: ["b", "e", "zzz"]), ["g1", "g3"])
    }

    func testAnAssetInTwoGroupsAffectsBoth() {
        let index = GroupMembershipIndex(groups: ["g1": ["a", "b"], "g2": ["b", "c"]])
        XCTAssertEqual(index.groupsAffected(by: ["b"]), ["g1", "g2"])
    }

    func testUpsertReplacesMembersAndRemoveForgetsThem() {
        var index = GroupMembershipIndex(groups: ["g1": ["a", "b"]])
        index.upsert(groupID: "g1", members: ["a", "c"])
        XCTAssertTrue(index.groupsAffected(by: ["b"]).isEmpty, "b left the group")
        XCTAssertEqual(index.groupsAffected(by: ["c"]), ["g1"])
        index.remove(groupID: "g1")
        XCTAssertTrue(index.groupsAffected(by: ["a", "c"]).isEmpty)
        XCTAssertNil(index.members(of: "g1"))
    }

    /// Property: after any sequence of upserts/removes the index agrees with a brute-force scan of all groups.
    func testRandomOperationsAlwaysMatchBruteForce() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<1_000 {
            var index = GroupMembershipIndex()
            var truth: [String: Set<String>] = [:]
            for _ in 0..<80 {
                let group = "g\(Int.random(in: 0..<50, using: &rng))"
                if Int.random(in: 0..<4, using: &rng) == 0 {
                    index.remove(groupID: group); truth[group] = nil
                } else {
                    let members = Set((0..<Int.random(in: 1...4, using: &rng)).map { _ in "a\(Int.random(in: 0..<200, using: &rng))" })
                    index.upsert(groupID: group, members: members); truth[group] = members
                }
            }
            let changed = Set((0..<10).map { _ in "a\(Int.random(in: 0..<200, using: &rng))" })
            let expected = Set(truth.filter { !$0.value.isDisjoint(with: changed) }.keys)
            XCTAssertEqual(index.groupsAffected(by: changed), expected)
            XCTAssertEqual(index.groupIDs, Set(truth.keys))
        }
    }
}
