import Foundation

/// Framework-independent, deterministic candidate discovery. False positives are permitted;
/// candidates are NEVER treated as evidence of redundancy.
public struct IndexedPhoto: Sendable, Equatable {
    public let id: String
    public let capturedAtSeconds: Int64?
    public let burstIdentifier: String?
    public let differenceHash: UInt64?
    public init(id: String, capturedAtSeconds: Int64?, burstIdentifier: String? = nil, differenceHash: UInt64? = nil) {
        self.id = id; self.capturedAtSeconds = capturedAtSeconds
        self.burstIdentifier = burstIdentifier; self.differenceHash = differenceHash
    }
}

public struct CandidatePair: Hashable, Sendable, Comparable {
    public let first: String
    public let second: String
    public init(_ first: String, _ second: String) {
        self.first = min(first, second); self.second = max(first, second)
    }
    public static func <(lhs: Self, rhs: Self) -> Bool {
        lhs.first == rhs.first ? lhs.second < rhs.second : lhs.first < rhs.first
    }
}

public enum CandidateIndex {
    public static func hamming(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }

    /// Each 64-bit hash has four 16-bit bands. Equal bands propose candidates, then full
    /// hash distance is evaluated. This is LSH, NOT proof of similarity or uniqueness.
    public static func propose(_ items: [IndexedPhoto],
                               maxSecondsApart: Int64 = 12,
                               maximumPairs: Int = 100_000,
                               maximumBucketSize: Int = 256) -> [CandidatePair] {
        guard maximumPairs > 0 else { return [] }
        var pairs: Set<CandidatePair> = []
        let sorted = items.sorted { a,b in
            let ta = a.capturedAtSeconds ?? Int64.min
            let tb = b.capturedAtSeconds ?? Int64.min
            return ta == tb ? a.id < b.id : ta < tb
        }
        var burstBuckets: [String: [String]] = [:]
        var hashBuckets: [UInt64: [(String, UInt64)]] = [:]
        for item in items {
            if let burst = item.burstIdentifier, !burst.isEmpty { burstBuckets[burst, default: []].append(item.id) }
            if let hash = item.differenceHash {
                for band in 0..<4 {
                    let segment = (hash >> UInt64(band * 16)) & 0xffff
                    let bucketKey = (UInt64(band) << 16) | segment
                    hashBuckets[bucketKey, default: []].append((item.id, hash))
                }
            }
        }
        for bucket in burstBuckets.keys.sorted() {
            let ids = (burstBuckets[bucket] ?? []).sorted()
            if ids.count > maximumBucketSize { continue }
            for i in ids.indices { for j in (i + 1)..<ids.count {
                pairs.insert(CandidatePair(ids[i], ids[j]))
                if pairs.count >= maximumPairs { return Array(pairs).sorted().prefix(maximumPairs).map { $0 } }
            }}
        }
        for key in hashBuckets.keys.sorted() {
            let entries = (hashBuckets[key] ?? []).sorted { $0.0 < $1.0 }
            if entries.count > maximumBucketSize { continue }
            for i in entries.indices { for j in (i + 1)..<entries.count {
                if hamming(entries[i].1, entries[j].1) <= 10 {
                    pairs.insert(CandidatePair(entries[i].0, entries[j].0))
                    if pairs.count >= maximumPairs { return Array(pairs).sorted().prefix(maximumPairs).map { $0 } }
                }
            }}
        }
        // Time-only candidates are intentionally LAST. Burst and visual hash matches
        // must not be starved by a dense timestamp neighborhood in large libraries.
        var left = 0
        for right in sorted.indices {
            guard let t = sorted[right].capturedAtSeconds else { continue }
            while left < right && (sorted[left].capturedAtSeconds ?? Int64.min) < t - maxSecondsApart { left += 1 }
            if right - left > maximumBucketSize { continue }
            for other in left..<right {
                if sorted[other].id == sorted[right].id { continue }
                pairs.insert(CandidatePair(sorted[other].id, sorted[right].id))
            }
            if pairs.count >= maximumPairs { return Array(pairs).sorted().prefix(maximumPairs).map { $0 } }
        }
        return pairs.sorted()
    }
}
