import XCTest
@testable import CleanSlateCore

final class ExactCandidatesTests: XCTestCase {
    private func key(_ id: String, t: Int64? = 1000, w: Int = 4032, h: Int = 3024, file: String? = nil, dur: Int64? = nil, type: Int = 1) -> ExactKey {
        ExactKey(id: id, mediaType: type, pixelWidth: w, pixelHeight: h, creationSecond: t, durationMillis: dur, originalFilename: file)
    }

    func testSameMetadataBucketsAndSingletonsDropped() {
        let out = ExactCandidates.buckets([key("a"), key("b"), key("c", t: 2000)])
        XCTAssertEqual(out.buckets, [["a", "b"]])
    }
    func testOrderIndependent() {
        let keys = [key("a"), key("b"), key("c"), key("d", t: 5), key("e", t: 5)]
        XCTAssertEqual(ExactCandidates.buckets(keys), ExactCandidates.buckets(keys.reversed()))
    }
    func testNilDateFallsThroughToFilenamePass() {
        let out = ExactCandidates.buckets([key("a", t: nil, file: "IMG_1.HEIC"), key("b", t: nil, file: "img_1.heic"), key("c", t: nil)])
        XCTAssertEqual(out.buckets, [["a", "b"]])
    }
    func testDifferentSizeOrTypeNeverBucketed() {
        XCTAssertTrue(ExactCandidates.buckets([key("a"), key("b", w: 3000)]).buckets.isEmpty)
        XCTAssertTrue(ExactCandidates.buckets([key("a"), key("b", type: 2)]).buckets.isEmpty)
    }
    func testVideosNeedSimilarDuration() {
        XCTAssertTrue(ExactCandidates.buckets([key("a", dur: 5_000, type: 2), key("b", dur: 9_000, type: 2)]).buckets.isEmpty)
        XCTAssertEqual(ExactCandidates.buckets([key("a", dur: 5_100, type: 2), key("b", dur: 5_400, type: 2)]).buckets, [["a", "b"]])
    }
    func testOversizedBucketsAreCountedNotSilentlyDropped() {
        let keys = (0..<70).map { key("p\($0)") } + [key("x", t: 1), key("y", t: 1)]
        let out = ExactCandidates.buckets(keys, maximumBucketSize: 64)
        XCTAssertEqual(out.buckets, [["x", "y"]])
        XCTAssertEqual(out.oversizedBuckets, 1)
        XCTAssertEqual(out.oversizedAssets, 70)
    }
    func testIdenticalMemberSetsAreNotDuplicatedAcrossPasses() {
        let out = ExactCandidates.buckets([key("a", file: "x.jpg"), key("b", file: "x.jpg")])
        XCTAssertEqual(out.buckets, [["a", "b"]])
    }
    /// 250k assets, 500 planted pairs: every pair is found, quickly.
    func testScalesTo250kWithAllPlantedPairsFound() {
        var keys: [ExactKey] = []
        keys.reserveCapacity(250_000)
        for i in 0..<250_000 { keys.append(key("p\(i)", t: Int64(i), w: 4000 + i % 5, h: 3000 + i % 7, file: "IMG_\(i).HEIC")) }
        for n in 0..<500 {
            let base = keys[n * 400]
            keys.append(ExactKey(id: "dup\(n)", mediaType: base.mediaType, pixelWidth: base.pixelWidth, pixelHeight: base.pixelHeight,
                                 creationSecond: base.creationSecond, originalFilename: base.originalFilename))
        }
        var out: ExactBuckets!
        let start = Date()
        out = ExactCandidates.buckets(keys)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(out.buckets.count, 500)
        XCTAssertTrue(out.buckets.allSatisfy { $0.count == 2 && $0.contains { $0.hasPrefix("dup") } })
        XCTAssertEqual(out.oversizedBuckets, 0)
        XCTAssertLessThan(elapsed, 5.0, "bucketing 250k assets took \(elapsed)s")
    }
}
