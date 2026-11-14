import XCTest
@testable import CleanSlateCore

final class ProtectionRuleSetTests: XCTestCase {
    private func t(_ s: Double) -> Date { Date(timeIntervalSince1970: s) }
    private func asset(_ id: String, enabled: Bool = true) -> ProtectionRule { ProtectionRule(scope: .asset(localIdentifier: id), enabled: enabled) }
    private func range(_ from: Double, _ to: Double, enabled: Bool = true) -> ProtectionRule {
        ProtectionRule(scope: .dateRange(start: LocalDay("2026-01-01")!, end: LocalDay("2026-01-02")!, timeZoneID: "UTC",
                                         startInclusive: t(from), endExclusive: t(to)), enabled: enabled)
    }
    private func album(_ id: String) -> ProtectionRule { ProtectionRule(scope: .album(localIdentifier: id)) }
    private func subject(_ id: String = "x", at: Double? = nil, albums: Set<String>? = []) -> ProtectionSubject {
        ProtectionSubject(id: id, capturedAt: at.map(t), albumIDs: albums)
    }

    func testEmptySetProtectsNothing() throws {
        let set = try ProtectionRuleSet(rules: [], revision: 1)
        XCTAssertEqual(set.verdict(subject(at: 5, albums: nil)), .unprotected)
        XCTAssertTrue(set.isEmpty)
    }

    func testAssetRuleMatchesByID() throws {
        let rule = asset("a")
        let set = try ProtectionRuleSet(rules: [rule], revision: 3)
        XCTAssertEqual(set.verdict(subject("a")), .protected(ruleIDs: [rule.id]))
        XCTAssertEqual(set.verdict(subject("b")), .unprotected)
        XCTAssertEqual(set.revision, 3)
    }

    func testAssetRuleIgnoresRevision() throws {
        // The subject carries no revision at all: an edited asset keeps its local identifier and its rule.
        let set = try ProtectionRuleSet(rules: [asset("a")], revision: 1)
        XCTAssertFalse(set.verdict(subject("a", at: nil)).allowsRemoval)
    }

    func testDisabledRulesAreIgnored() throws {
        let set = try ProtectionRuleSet(rules: [asset("a", enabled: false), range(0, 100, enabled: false)], revision: 1)
        XCTAssertEqual(set.verdict(subject("a", at: 50)), .unprotected)
        XCTAssertTrue(set.isEmpty)
    }

    func testDateRangeIsHalfOpen() throws {
        let set = try ProtectionRuleSet(rules: [range(100, 200)], revision: 1)
        XCTAssertEqual(set.verdict(subject(at: 99.9)), .unprotected)
        XCTAssertFalse(set.verdict(subject(at: 100)).allowsRemoval)
        XCTAssertFalse(set.verdict(subject(at: 199.9)).allowsRemoval)
        XCTAssertEqual(set.verdict(subject(at: 200)), .unprotected)
    }

    func testNilDateNeverMatches() throws {
        let set = try ProtectionRuleSet(rules: [range(-1e12, 1e12)], revision: 1)
        XCTAssertEqual(set.verdict(subject(at: nil)), .unprotected)
    }

    func testOverlappingAndTouchingRangesMergeAndKeepAllIDs() throws {
        let a = range(0, 100), b = range(50, 150), c = range(150, 200), far = range(500, 600)
        let set = try ProtectionRuleSet(rules: [far, c, a, b], revision: 1)
        XCTAssertEqual(set.verdict(subject(at: 75)), .protected(ruleIDs: [a.id, b.id, c.id]))   // merged interval keeps the union
        XCTAssertFalse(set.verdict(subject(at: 150)).allowsRemoval)
        XCTAssertFalse(set.verdict(subject(at: 199)).allowsRemoval)
        XCTAssertEqual(set.verdict(subject(at: 300)), .unprotected)
        XCTAssertFalse(set.verdict(subject(at: 550)).allowsRemoval)
        XCTAssertEqual(set.verdict(subject(at: 600)), .unprotected)
    }

    func testAssetAndDateBothReportTheirRules() throws {
        let a = asset("x"), r = range(0, 100)
        let set = try ProtectionRuleSet(rules: [a, r], revision: 1)
        XCTAssertEqual(set.verdict(subject("x", at: 10)), .protected(ruleIDs: [a.id, r.id]))
    }

    func testAlbumRuleUnknownMembershipIsIndeterminate() throws {
        let set = try ProtectionRuleSet(rules: [album("A")], revision: 1)
        XCTAssertEqual(set.verdict(subject(albums: nil)), .indeterminate(.albumMembershipUnknown))
        XCTAssertFalse(set.verdict(subject(albums: nil)).allowsRemoval)
    }

    func testAlbumRuleKnownMembershipMatches() throws {
        let rule = album("A")
        let set = try ProtectionRuleSet(rules: [rule], revision: 1)
        XCTAssertEqual(set.verdict(subject(albums: ["A", "B"])), .protected(ruleIDs: [rule.id]))
    }

    func testAlbumRuleKnownMembershipWithoutAlbumIsUnprotected() throws {
        let set = try ProtectionRuleSet(rules: [album("A")], revision: 1)
        XCTAssertEqual(set.verdict(subject(albums: [])), .unprotected)
        XCTAssertEqual(set.verdict(subject(albums: ["B"])), .unprotected)
    }

    func testProtectedBeatsIndeterminate() throws {
        let a = asset("x")
        let set = try ProtectionRuleSet(rules: [a, album("A")], revision: 1)
        XCTAssertEqual(set.verdict(subject("x", albums: nil)), .protected(ruleIDs: [a.id]))
        XCTAssertEqual(set.verdict(subject("y", albums: nil)), .indeterminate(.albumMembershipUnknown))
    }

    func testMalformedRulesThrow() {
        XCTAssertThrowsError(try ProtectionRuleSet(rules: [asset("")], revision: 1)) { XCTAssertEqual($0 as? ProtectionRuleSet.Invalid, .emptyAssetID) }
        XCTAssertThrowsError(try ProtectionRuleSet(rules: [album("")], revision: 1)) { XCTAssertEqual($0 as? ProtectionRuleSet.Invalid, .emptyAlbumID) }
        XCTAssertThrowsError(try ProtectionRuleSet(rules: [range(100, 100)], revision: 1)) { XCTAssertEqual($0 as? ProtectionRuleSet.Invalid, .emptyInterval) }
        XCTAssertThrowsError(try ProtectionRuleSet(rules: [range(200, 100)], revision: 1))
    }

    func testRuleCountLimits() throws {
        let assets = (0..<ProtectionRuleSet.maximumAssetRules).map { asset("a\($0)") }
        XCTAssertNoThrow(try ProtectionRuleSet(rules: assets, revision: 1))
        XCTAssertThrowsError(try ProtectionRuleSet(rules: assets + [asset("extra")], revision: 1)) {
            XCTAssertEqual($0 as? ProtectionRuleSet.Invalid, .tooManyAssetRules)
        }
        let ranges = (0..<ProtectionRuleSet.maximumDateRules).map { range(Double($0 * 10), Double($0 * 10 + 5)) }
        XCTAssertNoThrow(try ProtectionRuleSet(rules: ranges, revision: 1))
        XCTAssertThrowsError(try ProtectionRuleSet(rules: ranges + [range(5000, 5005)], revision: 1)) {
            XCTAssertEqual($0 as? ProtectionRuleSet.Invalid, .tooManyDateRules)
        }
    }

    func testDisabledMalformedRuleDoesNotThrow() {
        XCTAssertNoThrow(try ProtectionRuleSet(rules: [asset("", enabled: false)], revision: 1))
    }

    func testRuleCodableRoundTrip() throws {
        let rules = [asset("a"), album("b"), range(1, 2)]
        let data = try JSONEncoder().encode(rules)
        XCTAssertEqual(try JSONDecoder().decode([ProtectionRule].self, from: data), rules)
    }

    func testLargeSetLookupIsFast() throws {
        var rules = (0..<5_000).map { asset("a\($0)") }
        rules += (0..<100).map { range(Double($0 * 1000), Double($0 * 1000 + 500)) }
        let set = try ProtectionRuleSet(rules: rules, revision: 1)
        let start = Date()
        var protectedCount = 0
        for i in 0..<100_000 where !set.verdict(subject("p\(i)", at: Double(i))).allowsRemoval { protectedCount += 1 }
        XCTAssertGreaterThan(protectedCount, 0)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testCommitGateBlocksEveryNonReadyOrChangedState() {
        func gate(_ a: ProtectionAvailability, pending: Int = 0, start: Int64 = 1, now: Int64 = 1) -> IndeterminateReason? {
            ProtectionCommitGate.block(availability: a, pendingWrites: pending, startRevision: start, currentRevision: now)
        }
        XCTAssertNil(gate(.ready))
        XCTAssertEqual(gate(.loading), .rulesLoading)
        XCTAssertEqual(gate(.unavailable("x")), .rulesUnavailable)
        XCTAssertEqual(gate(.lost), .rulesUnavailable)
        XCTAssertEqual(gate(.ready, pending: 1), .ruleWritePending)
        XCTAssertEqual(gate(.ready, start: 1, now: 2), .ruleRevisionChanged)
        XCTAssertEqual(gate(.ready, start: 2, now: 1), .ruleRevisionChanged)   // a removal also blocks
    }
}
