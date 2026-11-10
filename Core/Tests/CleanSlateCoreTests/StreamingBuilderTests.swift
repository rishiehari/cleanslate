import XCTest
@testable import CleanSlateCore

/// Streaming == batch: the keyset builders must produce EXACTLY what the whole-library
/// batch functions produce, for random libraries and for the hand-built scenario vectors.
final class StreamingBuilderTests: XCTestCase {
    /// SplitMix64, reproducible from a seed.
    private struct RNG: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private func randomItems(count: Int, seed: UInt64) -> [SequenceItem] {
        var rng = RNG(seed: seed)
        let bursts = ["b1", "b2", "b3"]
        return (0..<count).map { n in
            let roll = Int(rng.next() % 100)
            let hasTime = roll < 90, hasHash = roll < 80, isBurst = roll >= 95
            return SequenceItem(
                id: "i\(n)",
                timeSeconds: hasTime ? Int64(rng.next() % 20_000) : nil,
                burstID: isBurst ? bursts[Int(rng.next() % UInt64(bursts.count))] : nil,
                hash: hasHash ? rng.next() & 0x3FFF_FFFF_FFFF_FFFF : nil)     // close hashes -> occasional runs
        }
    }

    private func randomKeys(count: Int, seed: UInt64) -> [ExactKey] {
        var rng = RNG(seed: seed)
        return (0..<count).map { n in
            ExactKey(id: "k\(n)",
                     mediaType: [1, 2][Int(rng.next() % 2)],
                     pixelWidth: [4032, 3024, 4000][Int(rng.next() % 3)],
                     pixelHeight: [3024, 4032, 3000][Int(rng.next() % 3)],
                     creationSecond: rng.next() % 5 == 0 ? nil : Int64(rng.next() % 5_000),
                     durationMillis: rng.next() % 2 == 0 ? Int64(rng.next() % 60_000) : nil,
                     originalFilename: rng.next() % 3 == 0 ? nil : "IMG_\(rng.next() % 200).HEIC")
        }
    }

    // MARK: SequenceGrouping.Streamer

    func testStreamerMatchesBatchOn500RandomLibraries() {
        for seed in 1...500 {
            let items = randomItems(count: 40 + Int(seed % 60), seed: UInt64(seed))
            let batch = SequenceGrouping.groups(items)
            for pageSize in [1, 7, 33, 10_000] {
                var streamer = SequenceGrouping.Streamer()
                for page in items.chunked(pageSize) { streamer.feed(page) }
                XCTAssertEqual(streamer.finish(), batch, "seed \(seed) page \(pageSize)")
            }
        }
    }

    func testStreamerMatchesBatchOnScenarioVectors() {
        let vectors: [[SequenceItem]] = [
            // A native burst far apart in time, plus a quick run.
            [SequenceItem(id: "a", timeSeconds: 10, burstID: "B"), SequenceItem(id: "b", timeSeconds: 90_000, burstID: "B"),
             SequenceItem(id: "c", timeSeconds: 500, hash: 0), SequenceItem(id: "d", timeSeconds: 502, hash: 1)],
            // Anti-chaining: slow pan, adjacent-close but end-to-end too far.
            [SequenceItem(id: "p0", timeSeconds: 0, hash: 0), SequenceItem(id: "p1", timeSeconds: 1, hash: 0b1111),
             SequenceItem(id: "p2", timeSeconds: 2, hash: 0b1111_1111), SequenceItem(id: "p3", timeSeconds: 3, hash: 0b1111_1111_1111)],
            // Size cap: 65 run members chunk to 30 + 30 + 5.
            (0..<65).map { SequenceItem(id: "r\($0)", timeSeconds: Int64($0), hash: 0) },
            // Missing time/hash never chain; two bursts interleaved by time.
            [SequenceItem(id: "x", timeSeconds: nil, hash: 0), SequenceItem(id: "y", timeSeconds: 5, hash: nil),
             SequenceItem(id: "u1", timeSeconds: 1, burstID: "U"), SequenceItem(id: "v1", timeSeconds: 2, burstID: "V"),
             SequenceItem(id: "u2", timeSeconds: 3, burstID: "U"), SequenceItem(id: "v2", timeSeconds: 4, burstID: "V")],
        ]
        for (index, items) in vectors.enumerated() {
            let batch = SequenceGrouping.groups(items)
            var streamer = SequenceGrouping.Streamer()
            for page in items.chunked(2) { streamer.feed(page) }     // awkward page size on purpose
            XCTAssertEqual(streamer.finish(), batch, "vector \(index)")
        }
    }

    // MARK: ExactBucketBuilder

    func testBucketBuilderMatchesBatchOn500RandomLibraries() {
        for seed in 1...500 {
            let keys = randomKeys(count: 30 + Int(seed % 90), seed: UInt64(seed) &+ 7_000)
            let batch = ExactCandidates.buckets(keys)
            for pageSize in [1, 13, 64, 10_000] {
                var builder = ExactCandidates.ExactBucketBuilder()
                for page in keys.chunked(pageSize) { builder.add(page) }
                XCTAssertEqual(builder.finish(), batch, "seed \(seed) page \(pageSize)")
            }
        }
    }
}

private extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { start in Array(self[start..<Swift.min(start + size, count)]) }
    }
}
