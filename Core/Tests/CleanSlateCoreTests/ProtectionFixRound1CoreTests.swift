import XCTest
@testable import CleanSlateCore

/// N05 fix round 1 (m1, m3, M2 policy input).
final class ProtectionFixRound1CoreTests: XCTestCase {
    private struct Boom: Error {}

    func testSubjectDefaultAlbumMembershipIsUnknown() throws {
        XCTAssertNil(ProtectionSubject(id: "x", capturedAt: nil).albumIDs)
        let set = try ProtectionRuleSet(rules: [ProtectionRule(scope: .album(localIdentifier: "A"))], revision: 1)
        XCTAssertEqual(set.verdict(ProtectionSubject(id: "x", capturedAt: nil)), .indeterminate(.albumMembershipUnknown))
    }

    func testSkippedLocalDayIsRejected() {
        // Samoa skipped 2011-12-30 entirely (UTC+13 -> UTC-11 jump).
        let day = LocalDay("2011-12-30")!
        XCTAssertNil(ProtectionDateResolver.interval(start: day, end: day, timeZoneID: "Pacific/Apia"))
        let before = LocalDay("2011-12-29")!, after = LocalDay("2011-12-31")!
        XCTAssertNotNil(ProtectionDateResolver.interval(start: before, end: before, timeZoneID: "Pacific/Apia"))
        XCTAssertNotNil(ProtectionDateResolver.interval(start: after, end: after, timeZoneID: "Pacific/Apia"))
        // A range ending on the skipped day is also refused rather than silently widened.
        XCTAssertNil(ProtectionDateResolver.interval(start: before, end: day, timeZoneID: "Pacific/Apia"))
    }

    func testEvidenceOfExistingRulesOverridesNeverCreated() {
        func decide(_ read: Result<Int64, Error>?, durable: Bool = true) -> ProtectionAvailability {
            ProtectionLoadPolicy.availability(read: read, everCreated: false, mirroredRevision: 0, storeDurable: durable,
                                              evidenceOfExistingRules: true)
        }
        if case .unavailable = decide(.failure(Boom())) {} else { XCTFail("read failure with evidence must be unavailable") }
        if case .unavailable = decide(.success(1), durable: false) {} else { XCTFail("fallback store with evidence must be unavailable") }
        XCTAssertEqual(decide(.success(3)), .ready, "a readable durable store is fine whatever the evidence")
        XCTAssertEqual(decide(nil), .loading)
        XCTAssertEqual(ProtectionLoadPolicy.availability(read: .failure(Boom()), everCreated: false, mirroredRevision: 0, storeDurable: true), .ready,
                       "no evidence and never created stays ready")
    }
}
