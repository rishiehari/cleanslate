import Foundation

/// Cheap metadata that byte-identical copies share. Used ONLY to decide which assets are worth
/// hashing in full; a bucket is never evidence that two assets are identical.
public struct ExactKey: Sendable, Equatable {
    public let id: String
    public let mediaType: Int            // 1 image, 2 video (PHAssetMediaType raw values)
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let creationSecond: Int64?
    public let durationMillis: Int64?
    public let originalFilename: String?
    public init(id: String, mediaType: Int, pixelWidth: Int, pixelHeight: Int,
                creationSecond: Int64?, durationMillis: Int64? = nil, originalFilename: String? = nil) {
        self.id = id; self.mediaType = mediaType; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
        self.creationSecond = creationSecond; self.durationMillis = durationMillis
        self.originalFilename = originalFilename
    }
}

public struct ExactBuckets: Sendable, Equatable {
    /// Each bucket has 2...maximumBucketSize ids, sorted. Buckets are sorted for determinism.
    public let buckets: [[String]]
    /// Buckets skipped because they were too large to hash exhaustively (reported, never silently dropped).
    public let oversizedBuckets: Int
    public let oversizedAssets: Int
}

public enum ExactCandidates {
    /// Pass 1: same type, size, creation second (and duration second for video).
    /// Pass 2: same type, size and original filename (covers copies whose dates differ).
    public static func buckets(_ keys: [ExactKey], maximumBucketSize: Int = 64) -> ExactBuckets {
        struct Pass1: Hashable { let t: Int, w: Int, h: Int, c: Int64, d: Int64 }
        struct Pass2: Hashable { let t: Int, w: Int, h: Int, f: String }
        var first: [Pass1: [String]] = [:]
        var second: [Pass2: [String]] = [:]
        for key in keys {
            if let c = key.creationSecond {
                first[Pass1(t: key.mediaType, w: key.pixelWidth, h: key.pixelHeight, c: c,
                            d: (key.durationMillis ?? 0) / 1000), default: []].append(key.id)
            }
            if let f = key.originalFilename, !f.isEmpty {
                second[Pass2(t: key.mediaType, w: key.pixelWidth, h: key.pixelHeight, f: f.lowercased()), default: []].append(key.id)
            }
        }
        var seen: Set<[String]> = []
        var result: [[String]] = []
        var oversized = 0, oversizedAssets = 0
        let creation = Dictionary(keys.compactMap { key in key.creationSecond.map { (key.id, $0) } }, uniquingKeysWith: { a, _ in a })
        func consume(_ members: [String], allowSplit: Bool = true) {
            let ids = Array(Set(members)).sorted()
            guard ids.count >= 2 else { return }
            if ids.count > maximumBucketSize {
                // Too many to hash blindly: split by creation minute first, so real copies stay reachable.
                if allowSplit {
                    // Split where the creation times have a gap of more than a minute (no hard minute edges).
                    let dated = ids.filter { creation[$0] != nil }.sorted { (creation[$0] ?? 0, $0) < (creation[$1] ?? 0, $1) }
                    let leftover = ids.count - dated.count
                    var cluster: [String] = []
                    for id in dated {
                        if let last = cluster.last, (creation[id] ?? 0) - (creation[last] ?? 0) > 60 {
                            consume(cluster, allowSplit: false); cluster = []
                        }
                        cluster.append(id)
                    }
                    consume(cluster, allowSplit: false)
                    if leftover > 0 { oversized += 1; oversizedAssets += leftover }
                } else {
                    oversized += 1; oversizedAssets += ids.count
                }
                return
            }
            if seen.insert(ids).inserted { result.append(ids) }
        }
        first.values.forEach { consume($0) }
        second.values.forEach { consume($0) }
        result.sort { $0.lexicographicallyPrecedes($1) }
        return ExactBuckets(buckets: result, oversizedBuckets: oversized, oversizedAssets: oversizedAssets)
    }
}
