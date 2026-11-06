import Foundation

public struct SequenceItem: Sendable, Equatable {
    public let id: String
    public let timeSeconds: Int64?
    public let burstID: String?
    public let hash: UInt64?
    public init(id: String, timeSeconds: Int64?, burstID: String? = nil, hash: UInt64? = nil) {
        self.id = id; self.timeSeconds = timeSeconds; self.burstID = burstID; self.hash = hash
    }
}

/// Builds REVIEW SETS: bursts and quick runs of look-alike shots the user can cull in one screen.
/// A review set is never evidence that anything is redundant; it only decides what is shown together.
public enum SequenceGrouping {
    public struct Configuration: Sendable {
        public var maximumGroupSize = 30
        public var maximumSecondsApart: Int64 = 3
        /// Adjacent shots must be at most this many hash bits apart...
        public var adjacentDistance = 12
        /// ...and the FIRST and LAST shot at most this many (anti-chaining: a slow pan must not become one group).
        public var endToEndDistance = 24
        public init() {}
    }

    public static func groups(_ items: [SequenceItem], configuration: Configuration = .init()) -> [[String]] {
        var result: [[String]] = []
        var inBurst: Set<String> = []

        // 1. Native bursts (any time span), oldest first, chunked to the maximum size.
        let bursts = Dictionary(grouping: items.filter { ($0.burstID ?? "").isEmpty == false }, by: { $0.burstID ?? "" })
        for key in bursts.keys.sorted() {
            let ordered = (bursts[key] ?? []).sorted(by: Self.byTimeThenID)
            for chunk in stride(from: 0, to: ordered.count, by: configuration.maximumGroupSize) {
                let ids = ordered[chunk..<min(chunk + configuration.maximumGroupSize, ordered.count)].map(\.id)
                if ids.count >= 2 { result.append(ids) }
            }
            inBurst.formUnion(ordered.map(\.id))
        }

        // 2. Quick runs of similar shots that are not part of a burst.
        let loose = items.filter { !inBurst.contains($0.id) && $0.timeSeconds != nil && $0.hash != nil }.sorted(by: Self.byTimeThenID)
        var run: [SequenceItem] = []
        func flush() {
            if run.count >= 2 { result.append(run.map(\.id)) }
            run = []
        }
        for item in loose {
            if let last = run.last, let first = run.first,
               let t = item.timeSeconds, let lt = last.timeSeconds, let h = item.hash, let lh = last.hash, let fh = first.hash,
               t - lt <= configuration.maximumSecondsApart,
               hamming(h, lh) <= configuration.adjacentDistance,
               hamming(h, fh) <= configuration.endToEndDistance,
               run.count < configuration.maximumGroupSize {
                run.append(item)
            } else {
                flush()
                run = [item]
            }
        }
        flush()
        return result
    }

    private static func byTimeThenID(_ a: SequenceItem, _ b: SequenceItem) -> Bool {
        (a.timeSeconds ?? Int64.min, a.id) < (b.timeSeconds ?? Int64.min, b.id)
    }

    private static func hamming(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }
}
