import XCTest
import CleanSlateCore
@testable import CleanSlate

/// F03.5: the exact-digest queue is narrowed to near-identical same-size pairs, album membership
/// comes from targeted lookups over found members only, and album members stay protected.
@MainActor
final class ExactNarrowingTests: XCTestCase {
    private let dims: [String: (width: Int, height: Int)] = ["a": (4032, 3024), "b": (4032, 3024), "c": (4032, 3024),
                                                             "d": (4032, 3024), "e": (4000, 3000), "f": (4000, 2250)]
    private func hashes(_ pairs: [(String, UInt64)]) -> [String: UInt64] { Dictionary(uniqueKeysWithValues: pairs) }

    func testNearPairsAboveHamming2OrMismatchedSizeAreNeverEnqueued() {
        let buckets = ExactBuckets(buckets: [["bucket-a", "bucket-b"]], oversizedBuckets: 0, oversizedAssets: 0)
        let pairs = [CandidatePair("a", "b"),      // Hamming 6: near, but not near-identical
                     CandidatePair("c", "d"),      // Hamming 2, same size: re-saved copy candidate
                     CandidatePair("e", "f")]      // Hamming 0 but different pixel size
        let h = hashes([("a", 0xFFFF), ("b", 0xFFFF ^ 0b111111), ("c", 0xAAAA), ("d", 0xAAAA ^ 0b11),
                        ("e", 0x5555), ("f", 0x5555)])
        let enqueue = ScanEngine.enqueueDigestCandidates(buckets: buckets, pairs: pairs, hashes: h, dimensions: dims, cap: 4_000)
        XCTAssertEqual(enqueue.order, ["bucket-a", "bucket-b", "c", "d"], "only exact-bucket members and Hamming<=2 same-size pairs are digested")
        XCTAssertEqual(enqueue.droppedByCap, 0)
        XCTAssertEqual(enqueue.excludedByNarrowing, 4, "the Hamming-6 pair and the size-mismatch pair are reported as excluded (their 4 members), not as 'skipped by limit'")
    }

    func testMissingHashOrDimensionsExcludesThePair() {
        let buckets = ExactBuckets(buckets: [], oversizedBuckets: 0, oversizedAssets: 0)
        let h = hashes([("a", 0xFFFF)])                      // b has no hash
        let enqueue = ScanEngine.enqueueDigestCandidates(buckets: buckets, pairs: [CandidatePair("a", "b")], hashes: h, dimensions: dims, cap: 4_000)
        XCTAssertTrue(enqueue.order.isEmpty)
        XCTAssertEqual(enqueue.excludedByNarrowing, 2, "a pair without hashes counts as excluded, not truncated")
    }

    func testDigestQueueCapFollowsScopeCount() {
        let members = (0..<10).map { "m\($0)" }
        let buckets = ExactBuckets(buckets: [members], oversizedBuckets: 0, oversizedAssets: 0)
        let enqueue = ScanEngine.enqueueDigestCandidates(buckets: buckets, pairs: [], hashes: [:], dimensions: [:], cap: 4)
        XCTAssertEqual(enqueue.order.count, 4, "min(4_000, scopeCount) bounds the queue")
        XCTAssertEqual(enqueue.droppedByCap, 6, "true cap truncation is reported separately")
    }

    /// m7: narrowing exclusions must NOT appear in exactSkippedByLimit (that field is true cap
    /// truncation, 'left for the next scan'); they are counted separately.
    func testNarrowingExclusionsAreNotReportedAsSkippedByLimit() async throws {
        let library = FakePhotoLibrary()
        library.add("k1", content: "identical", bytes: 5_000, at: 500)
        library.add("k2", content: "identical", bytes: 5_000, at: 500)
        // Same dhash (same spec base), far apart in time: a near pair that the Hamming<=2 +
        // same-size narrowing will EXCLUDE (dhash distance of the spec is > 2 bits).
        let spec = FakePhotoLibrary.RenderSpec(base: 41)
        library.add("n1", content: "x", at: 1_000_000, spec: spec)
        library.add("n2", content: "y", at: 9_000_000, spec: FakePhotoLibrary.RenderSpec(base: 41, shiftX: 3))
        let model = try ScanTestRig.model(library: library)
        await model.runScan()
        XCTAssertEqual(model.statistics.exactSkippedByLimit, 0, "narrowing exclusions are not 'left for next scan'")
        XCTAssertGreaterThan(model.statistics.exactExcludedByNarrowing, 0)
    }

    func testIdenticalPairIsStillDigestedAndVerified() async throws {
        let library = FakePhotoLibrary()
        library.add("k1", content: "identical", bytes: 5_000, at: 500)
        library.add("k2", content: "identical", bytes: 5_000, at: 500)
        let model = try ScanTestRig.model(library: library)
        await model.runScan()
        XCTAssertEqual(model.statistics.exactAssetsHashed, 2, "identical local copies are verified, not narrowed away")
        XCTAssertEqual(model.groups.filter { $0.kind == .exact }.count, 1)
    }

    /// The scan never does a whole-library album pass: every targeted lookup is a subset of the
    /// members of found groups (plus standalone candidates), and an album member in a group is
    /// still flagged and kept.
    func testAlbumLookupIsScopedToFoundMembersAndAlbumMembersStayProtected() async throws {
        let library = FakePhotoLibrary()
        library.add("plain", content: "same", bytes: 5_000, at: 500)
        library.add("in-album", content: "same", bytes: 5_000, at: 500)
        library.albumMemberTable = ["in-album"]
        let model = try ScanTestRig.model(library: library)
        await model.runScan()

        XCTAssertFalse(library.albumMemberAmongCalls.isEmpty, "the scan used the targeted lookup")
        let group = model.groups.first { $0.kind == .exact }
        XCTAssertNotNil(group)
        let members = Set(group!.all.map(\.id))
        for call in library.albumMemberAmongCalls {
            XCTAssertTrue(Set(call).isSubset(of: members), "album lookup \(call) must stay within found-group members")
        }
        let albumPhoto = group!.all.first { $0.id == "in-album" }
        XCTAssertNotNil(albumPhoto)
        XCTAssertTrue(albumPhoto!.record.flags.contains(.curatedAlbum), "the targeted lookup still protects the album member")
        XCTAssertEqual(group!.keeper.id, "in-album", "a protected member is preferred as keeper")
    }
}
