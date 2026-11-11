import XCTest
import CleanSlateCore
@testable import CleanSlate

/// Keyset-paged store queries (F03.4a): each page costs the same no matter how much was done,
/// and paged results are exactly the whole-library results.
@MainActor
final class PagedQueryTests: XCTestCase {
    private var store: LibraryStore!

    override func setUp() async throws {
        store = try LibraryStore(path: nil)
    }

    private func photo(_ id: String, at: Int64?, burst: String? = nil, width: Int = 4032, height: Int = 3024) -> PhotoSnapshot {
        PhotoSnapshot(id: id, record: AssetRecord(id: id, revision: "r1"), capturedAt: at.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                      burstID: burst, width: width, height: height)
    }

    func testExactKeyPageExhaustionMatchesWholeLibrary() async throws {
        let assets = (0..<250).map { photo("e\($0)", at: Int64(1_000 + $0)) }
        try await store.upsert(assets)
        try await store.setMeta(LibrarySync.Meta.complete, Data([1]))   // no features needed
        var collected: [ExactKey] = []
        var cursor: Int64 = 0
        while true {
            let page = await store.exactKeyPage(afterRowID: cursor, limit: 100)
            collected += page.keys
            guard !page.keys.isEmpty else { break }
            cursor = page.lastRowID
        }
        let allKeys = await store.exactKeys()
        XCTAssertEqual(collected, allKeys)
        XCTAssertEqual(collected.count, 250)
    }

    func testSequencePageMatchesByTimeThenIDWithNullsAndTies() async throws {
        var assets: [PhotoSnapshot] = []
        assets += [photo("nil-b", at: nil), photo("nil-a", at: nil)]          // NULLs first, id order
        assets += [photo("t5-b", at: 5), photo("t5-a", at: 5), photo("t9", at: 9)]
        assets += (0..<20).map { photo("u\($0)", at: Int64(100 + $0 * 3)) }
        try await store.upsert(assets)
        try await store.putFeatures(assets.map { ($0.id, "r1", UInt64($0.id.utf8.reduce(0) { $0 &* 31 &+ Int($1) })) },
                                    version: ScanEngine.featureVersion)

        let batch = await store.sequenceItems(version: ScanEngine.featureVersion)
            .sorted { ($0.timeSeconds ?? .min, $0.id) < ($1.timeSeconds ?? .min, $1.id) }
        var paged: [SequenceItem] = []
        var time: Int64? = nil
        var id = ""
        while true {
            let page = await store.sequencePage(afterTime: time, afterID: id, limit: 4, version: ScanEngine.featureVersion)
            paged += page.items
            guard !page.items.isEmpty else { break }
            time = page.lastTime; id = page.lastID
        }
        XCTAssertEqual(paged, batch, "paged sequence items == whole-library, NULL times and ties included")
        XCTAssertEqual(paged.first?.timeSeconds, nil, "NULL created_s sorts first")
        XCTAssertEqual(paged.prefix(2).map(\.id), ["nil-a", "nil-b"])
    }

    func testMomentBucketCap30SkipsLargeBurstsAndCountsNothingSilently() async throws {
        // Burst frames far apart in time, so ONLY the burst path could pair them: the cap must
        // exclude the whole 31-frame burst (review sets still cover those photos).
        let burst = (0..<31).map { photo("big-\($0)", at: Int64($0) * 3_600, burst: "big") }
        let small = (0..<3).map { photo("small-\($0)", at: Int64(100 + $0)) }
        try await store.upsert(burst + small)
        let result = await store.momentPairs(maxSecondsApart: 12, maximumBucketSize: 30, maximumPairs: 1_000)
        for pair in result.pairs {
            XCTAssertFalse(pair.first.hasPrefix("big-") && pair.second.hasPrefix("big-"), "the 31-frame burst exceeds the cap and must not pair")
        }
        XCTAssertEqual(result.pairs.count, 3, "only the 3-pair small window remains (C(3,2)=3)")
        XCTAssertEqual(result.oversizedBuckets, 1, "the oversized burst bucket is reported (m9)")
        XCTAssertEqual(result.pairsDroppedByCap, 0)
    }

    /// M5: the burst section honors maximumPairs and reports the overflow (m9).
    func testMomentPairsBurstSectionEnforcesTheCapAndReportsOverflow() async throws {
        // 40 bursts of 25 frames (<= bucket cap 30) -> 40 x C(25,2) = 12,000 potential burst pairs.
        var assets: [PhotoSnapshot] = []
        for b in 0..<40 {
            for f in 0..<25 {
                assets.append(photo("b\(b)-\(f)", at: Int64(b) * 86_400 + Int64(f), burst: "burst-\(b)"))
            }
        }
        try await store.upsert(assets)
        let result = await store.momentPairs(maxSecondsApart: 12, maximumBucketSize: 30, maximumPairs: 5_000)
        XCTAssertLessThanOrEqual(result.pairs.count, 5_000, "the cap holds in the burst section")
        XCTAssertGreaterThan(result.pairsDroppedByCap, 0, "the ungenerated pairs are reported, never silent")
        XCTAssertEqual(result.oversizedBuckets, 0)
    }

    func testNearPairCapTruncatesAndSkipsAreCounted() async throws {
        let ids = (0..<20).map { "p\($0)" }
        try await store.upsert(ids.map { photo($0, at: nil) })
        try await store.putFeatures(ids.map { ($0, "r1", UInt64(0)) }, version: ScanEngine.featureVersion)   // one giant bucket
        let capped = await store.nearHashPairs(maxHamming: 10, maximumBucketSize: 64, maximumPairs: 7)
        XCTAssertEqual(capped.pairs.count, 7, "the tier cap truncates")
        let tiny = await store.nearHashPairs(maxHamming: 10, maximumBucketSize: 4, maximumPairs: 10_000)
        XCTAssertTrue(tiny.pairs.isEmpty)
        XCTAssertEqual(tiny.skippedBuckets, 4, "each of the four bands reports its oversized bucket")
    }
}
