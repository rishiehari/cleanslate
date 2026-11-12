import XCTest
@testable import CleanSlateCore

final class ProtectionLoadPolicyTests: XCTestCase {
    private struct Boom: Error {}
    private func decide(_ read: Result<Int64, Error>?, created: Bool, mirrored: Int64 = 0, durable: Bool = true) -> ProtectionAvailability {
        ProtectionLoadPolicy.availability(read: read, everCreated: created, mirroredRevision: mirrored, storeDurable: durable)
    }
    private func isUnavailable(_ a: ProtectionAvailability) -> Bool { if case .unavailable = a { return true } else { return false } }

    func testNoReadYetIsLoading() { XCTAssertEqual(decide(nil, created: true), .loading) }
    func testHealthyStoreIsReady() { XCTAssertEqual(decide(.success(1), created: false), .ready) }
    func testReadFailureNeverCreatedIsReady() { XCTAssertEqual(decide(.failure(Boom()), created: false), .ready) }
    func testReadFailureAfterCreationIsUnavailable() { XCTAssertTrue(isUnavailable(decide(.failure(Boom()), created: true))) }
    func testFallbackStoreNeverCreatedIsReady() { XCTAssertEqual(decide(.success(1), created: false, durable: false), .ready) }
    func testFallbackStoreAfterCreationIsUnavailable() {
        XCTAssertTrue(isUnavailable(decide(.success(1), created: true, mirrored: 4, durable: false)))
    }
    func testRevisionBelowMirrorIsLost() { XCTAssertEqual(decide(.success(1), created: true, mirrored: 5), .lost) }
    func testRevisionEqualOrAboveMirrorIsReady() {
        XCTAssertEqual(decide(.success(5), created: true, mirrored: 5), .ready)
        XCTAssertEqual(decide(.success(9), created: true, mirrored: 5), .ready)
    }
    func testRevisionBelowMirrorWithoutCreationIsReady() { XCTAssertEqual(decide(.success(1), created: false, mirrored: 5), .ready) }
}
