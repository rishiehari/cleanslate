import XCTest
import CleanSlateCore
@testable import CleanSlate

final class LibraryStoreTests: XCTestCase {
    private func photo(_ id: String, rev: String = "r1", at: Int64? = 1_000, flags: Set<PreservationFlag> = [],
                       video: Bool = false, burst: String? = nil, file: String? = "IMG.HEIC") -> PhotoSnapshot {
        PhotoSnapshot(id: id, record: AssetRecord(id: id, revision: rev, flags: flags),
                      capturedAt: at.map { Date(timeIntervalSince1970: TimeInterval($0)) }, burstID: burst,
                      width: 4032, height: 3024, originalFilename: file, isVideo: video,
                      durationSeconds: video ? 12.5 : 0, subtypes: 4)
    }

    private func tempPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString).sqlite").path
    }

    func testFreshStoreIsAtCurrentSchemaVersion() async throws {
        let store = try LibraryStore(path: nil)
        let version = await store.userVersion
        XCTAssertEqual(version, LibraryStore.schemaVersion)
    }

    func testAssetRoundTripPreservesEveryField() async throws {
        let store = try LibraryStore(path: nil)
        let original = photo("a", flags: [.favorite, .livePhoto], video: true, burst: "b1")
        try await store.upsert([original, photo("nodate", at: nil, file: nil)])
        let loaded = await store.snapshots(ids: ["a", "nodate"])
        XCTAssertEqual(loaded["a"], original)
        XCTAssertNil(loaded["nodate"]?.capturedAt)
        XCTAssertNil(loaded["nodate"]?.originalFilename)
    }

    func testUpsertIsIdempotentAndUpdatesInPlace() async throws {
        let store = try LibraryStore(path: nil)
        try await store.upsert([photo("a")])
        try await store.upsert([photo("a"), photo("a", rev: "r2", flags: [.favorite])])
        let count = await store.assetCount()
        XCTAssertEqual(count, 1)
        let a = await store.snapshots(ids: ["a"])["a"]
        XCTAssertEqual(a?.record.revision, "r2")
        XCTAssertEqual(a?.record.flags, [.favorite])
    }

    func testChangedRevisionDropsStaleFeatures() async throws {
        let store = try LibraryStore(path: nil)
        try await store.upsert([photo("a")])
        try await store.putFeatures([("a", "r1", 0xDEADBEEF)], version: 1)
        let cached = await store.dhash(id: "a", revision: "r1")
        XCTAssertEqual(cached, 0xDEADBEEF)
        try await store.upsert([photo("a", rev: "r2")])
        let afterChange = await store.dhash(id: "a", revision: "r1")
        XCTAssertNil(afterChange, "a fingerprint of the old revision must not survive an edit")
        let needing = await store.imageAssetsNeedingFeatures(limit: 10, version: 1)
        XCTAssertEqual(needing.photos.map(\.id), ["a"])
    }

    func testDeletedAssetsDisappearFromEveryQuery() async throws {
        let store = try LibraryStore(path: nil)
        try await store.upsert([photo("a"), photo("b")])
        try await store.markDeleted(["a"])
        let count = await store.assetCount()
        let keys = await store.exactKeys()
        let page = await store.page(offset: 0, limit: 10)
        let snaps = await store.snapshots(ids: ["a", "b"])
        XCTAssertEqual(count, 1)
        XCTAssertEqual(keys.map(\.id), ["b"])
        XCTAssertEqual(page.map(\.id), ["b"])
        XCTAssertNil(snaps["a"])
        try await store.upsert([photo("a")])                      // reappearing (e.g. restored) revives it
        let revived = await store.assetCount()
        XCTAssertEqual(revived, 2)
    }

    func testPagingWalksNewestFirstWithoutOverlap() async throws {
        let store = try LibraryStore(path: nil)
        try await store.upsert((0..<25).map { photo("p\($0)", at: Int64($0)) })
        var seen: [String] = []
        var offset = 0
        while true {
            let chunk = await store.page(offset: offset, limit: 10)
            if chunk.isEmpty { break }
            seen += chunk.map(\.id); offset += chunk.count
        }
        XCTAssertEqual(seen.count, 25)
        XCTAssertEqual(Set(seen).count, 25)
        XCTAssertEqual(seen.first, "p24")
    }

    func testFeatureCursorWalksEveryAssetOnceAndCostsTheSamePerBatch() async throws {
        let store = try LibraryStore(path: nil)
        try await store.upsert((0..<1_000).map { photo("p\($0)", at: Int64($0)) })
        var seen: [String] = []
        var cursor: Int64 = 0
        while true {
            let batch = await store.imageAssetsNeedingFeatures(afterRowID: cursor, limit: 150, version: 1)
            if batch.photos.isEmpty { break }
            cursor = batch.lastRowID
            seen += batch.photos.map(\.id)
            try await store.markFeaturesUnavailable(batch.photos.map { ($0.id, $0.record.revision) })
        }
        XCTAssertEqual(seen.count, 1_000)
        XCTAssertEqual(Set(seen).count, 1_000, "no asset is returned twice")
    }

    func testHighBitDifferenceHashSurvivesStorage() async throws {
        let store = try LibraryStore(path: nil)
        try await store.upsert([photo("a")])
        try await store.putFeatures([("a", "r1", UInt64.max - 5)], version: 1)
        let value = await store.dhash(id: "a", revision: "r1")
        XCTAssertEqual(value, UInt64.max - 5)
    }

    func testNearPairsFoundWithinHammingAndBandsOnly() async throws {
        let store = try LibraryStore(path: nil)
        try await store.upsert(["a", "b", "far", "alone"].map { photo($0, at: nil) })
        let base: UInt64 = 0x0123_4567_89AB_CDEF
        try await store.putFeatures([("a", "r1", base), ("b", "r1", base ^ 0b111),            // 3 bits apart
                                     ("far", "r1", base ^ 0xFFFF_0000_0000_FFFF),               // shares no band
                                     ("alone", "r1", ~base)], version: ScanEngine.featureVersion)
        let result = await store.nearHashPairs(maxHamming: 10, maximumBucketSize: 256, maximumPairs: 1_000)
        XCTAssertEqual(result.pairs, [CandidatePair("a", "b")])
        XCTAssertEqual(result.skippedBuckets, 0)
    }

    func testOversizedBandBucketsAreCountedNotSilentlyDropped() async throws {
        let store = try LibraryStore(path: nil)
        let ids = (0..<30).map { "p\($0)" }
        try await store.upsert(ids.map { photo($0, at: nil) })
        try await store.putFeatures(ids.map { ($0, "r1", UInt64(0)) }, version: ScanEngine.featureVersion)   // all identical hashes: one huge bucket per band
        let result = await store.nearHashPairs(maxHamming: 10, maximumBucketSize: 10, maximumPairs: 10_000)
        XCTAssertTrue(result.pairs.isEmpty)
        XCTAssertEqual(result.skippedBuckets, 4, "one oversized bucket in each of the four bands")
    }

    func testMomentPairsFromBurstsAndTimeWindows() async throws {
        let store = try LibraryStore(path: nil)
        try await store.upsert([photo("a", at: 100, burst: "B"), photo("b", at: 90_000, burst: "B"),   // same burst, far apart
                                photo("c", at: 500), photo("d", at: 505), photo("e", at: 9_999)])
        let result = await store.momentPairs(maxSecondsApart: 12, maximumBucketSize: 64, maximumPairs: 1_000)
        XCTAssertEqual(Set(result.pairs), [CandidatePair("a", "b"), CandidatePair("c", "d")])
    }

    func testMetaRoundTripAndDelete() async throws {
        let store = try LibraryStore(path: nil)
        try await store.setMeta("token", Data([1, 2, 3]))
        let first = await store.meta("token")
        XCTAssertEqual(first, Data([1, 2, 3]))
        try await store.setMeta("token", Data([9]))
        let replaced = await store.meta("token")
        XCTAssertEqual(replaced, Data([9]))
        try await store.setMeta("token", nil)
        let removed = await store.meta("token")
        XCTAssertNil(removed)
    }

    func testDataSurvivesReopenAndMigrationRunsOnce() async throws {
        let path = tempPath()
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        do {
            let store = try LibraryStore(path: path)
            try await store.upsert([photo("a")])
            try await store.setMeta("scan.offset", Data("500".utf8))
        }
        let reopened = try LibraryStore(path: path)
        let version = await reopened.userVersion
        let count = await reopened.assetCount()
        let offset = await reopened.meta("scan.offset")
        XCTAssertEqual(version, LibraryStore.schemaVersion)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(offset.flatMap { String(data: $0, encoding: .utf8) }, "500")
    }

    func testStoreFileIsExcludedFromBackup() async throws {
        let path = tempPath()
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        _ = try LibraryStore(path: path)
        let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testResetForgetsEverything() async throws {
        let store = try LibraryStore(path: nil)
        try await store.upsert([photo("a")])
        try await store.putFeatures([("a", "r1", 1)], version: 1)
        try await store.setMeta("x", Data([1]))
        try await store.reset()
        let assets = await store.assetCount(); let features = await store.featureCount(); let meta = await store.meta("x")
        XCTAssertEqual(assets, 0); XCTAssertEqual(features, 0); XCTAssertNil(meta)
    }
}
