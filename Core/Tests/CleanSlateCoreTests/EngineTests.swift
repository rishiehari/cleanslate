import XCTest
@testable import CleanSlateCore

final class EngineTests: XCTestCase {
    func testHamming() {
        XCTAssertEqual(CandidateIndex.hamming(0, 0), 0)
        XCTAssertEqual(CandidateIndex.hamming(0, UInt64.max), 64)
    }
    func testBurstsFormPairsAcrossTime() {
        let items = [IndexedPhoto(id: "a", capturedAtSeconds: 1, burstIdentifier: "burst"),
                     IndexedPhoto(id: "b", capturedAtSeconds: 800, burstIdentifier: "burst")]
        XCTAssertEqual(CandidateIndex.propose(items), [CandidatePair("a", "b")])
    }
    func testFarApartWithSameHashFindsCandidate() {
        let items = [IndexedPhoto(id: "a", capturedAtSeconds: 100, differenceHash: 0x1234),
                     IndexedPhoto(id: "b", capturedAtSeconds: 100_000, differenceHash: 0x1234)]
        XCTAssertEqual(CandidateIndex.propose(items), [CandidatePair("a", "b")])
    }
    func testNoTransitiveClaimFromIndex() {
        let items = [IndexedPhoto(id: "a", capturedAtSeconds: 1),
                     IndexedPhoto(id: "b", capturedAtSeconds: 2),
                     IndexedPhoto(id: "c", capturedAtSeconds: 30)]
        XCTAssertEqual(CandidateIndex.propose(items), [CandidatePair("a", "b")])
    }
    func testNoOverflowOrUnboundedBuckets() {
        let photos = (0..<200).map { IndexedPhoto(id: "\($0)", capturedAtSeconds: 1, differenceHash: 0) }
        XCTAssertLessThanOrEqual(CandidateIndex.propose(photos, maximumPairs: 12).count, 12)
    }
    func testCanonicalResourcesOrderIndependent() {
        let a = ResourceDigest(type:"photo", byteCount: 5, sha256: String(repeating: "a", count:64))
        let b = ResourceDigest(type:"pairedVideo", byteCount: 8, sha256: String(repeating:"b",count:64))
        XCTAssertEqual(ResourceSignatures.canonical([a,b]), ResourceSignatures.canonical([b,a]))
        XCTAssertEqual(ResourceSignatures.logicalBytes([a,b]), 13)
    }
    func testMissingResourceIsNotEqual() {
        let a = ResourceDigest(type:"photo", byteCount: 5, sha256: String(repeating: "a", count:64))
        XCTAssertNotEqual(ResourceSignatures.canonical([a]), ResourceSignatures.canonical([a,a]))
        XCTAssertNil(ResourceSignatures.canonical([]))
    }
    func testRankerStableAndFavoritePreservedInRanking() {
        let ranked = KeeperRanker.sorted([
            QualitySignals(id: "b", sharpness: 0.1, pixelCount: 100),
            QualitySignals(id: "a", sharpness: 0.9, pixelCount: 100)
        ])
        XCTAssertEqual(ranked.map(\.id), ["a", "b"])
    }
}
