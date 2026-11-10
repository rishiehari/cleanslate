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

    /// Streaming twin of `groups(_:)`. Feed time-ordered pages from a keyset query: burst members
    /// buffer per burst id, loose items extend the open run and close exactly as the batch version
    /// would. `finish()` returns the complete result — every burst group first (key order, chunked
    /// to the maximum size), then the loose runs in time order — identical to `groups(_:)`.
    public struct Streamer: Sendable {
        public private(set) var closedRuns: [[String]] = []
        private var burstBuffers: [String: [SequenceItem]] = [:]
        private var run: [SequenceItem] = []
        private let configuration: Configuration

        public init(configuration: Configuration = .init()) {
            self.configuration = configuration
        }

        public mutating func feed(_ items: [SequenceItem]) {
            for item in items {
                if let burst = item.burstID, !burst.isEmpty {
                    burstBuffers[burst, default: []].append(item)
                } else {
                    feedLoose(item)
                }
            }
        }

        /// The complete result, in the same order as `groups(_:)`.
        public mutating func finish() -> [[String]] {
            var result: [[String]] = []
            for key in burstBuffers.keys.sorted() {
                let ordered = (burstBuffers[key] ?? []).sorted(by: Self.byTimeThenID)
                for chunk in stride(from: 0, to: ordered.count, by: configuration.maximumGroupSize) {
                    let ids = ordered[chunk..<min(chunk + configuration.maximumGroupSize, ordered.count)].map(\.id)
                    if ids.count >= 2 { result.append(ids) }
                }
            }
            flushRun()
            result.append(contentsOf: closedRuns)
            return result
        }

        private mutating func feedLoose(_ item: SequenceItem) {
            guard item.timeSeconds != nil, item.hash != nil else {
                flushRun()      // an unchainable item between runs breaks them, like the batch filter
                return
            }
            if let last = run.last, let first = run.first,
               let t = item.timeSeconds, let lt = last.timeSeconds, let h = item.hash, let lh = last.hash, let fh = first.hash,
               t - lt <= configuration.maximumSecondsApart,
               Self.hamming(h, lh) <= configuration.adjacentDistance,
               Self.hamming(h, fh) <= configuration.endToEndDistance,
               run.count < configuration.maximumGroupSize {
                run.append(item)
            } else {
                flushRun()
                run = [item]
            }
        }

        private mutating func flushRun() {
            if run.count >= 2 { closedRuns.append(run.map(\.id)) }
            run = []
        }

        static func byTimeThenID(_ a: SequenceItem, _ b: SequenceItem) -> Bool {
            (a.timeSeconds ?? Int64.min, a.id) < (b.timeSeconds ?? Int64.min, b.id)
        }

        static func hamming(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }
    }

    public static func groups(_ items: [SequenceItem], configuration: Configuration = .init()) -> [[String]] {
        var streamer = Streamer(configuration: configuration)
        // 1. Native bursts (any time span), oldest first, chunked to the maximum size.
        let burstItems = items.filter { ($0.burstID ?? "").isEmpty == false }
        for burst in Set(burstItems.compactMap(\.burstID)) {
            streamer.feed(burstItems.filter { $0.burstID == burst })
        }
        // 2. Quick runs of similar shots that are not part of a burst, in time order.
        let inBurst = Set(burstItems.map(\.id))
        let loose = items.filter { !inBurst.contains($0.id) && $0.timeSeconds != nil && $0.hash != nil }
            .sorted(by: Streamer.byTimeThenID)
        streamer.feed(loose)
        return streamer.finish()
    }

    private static func byTimeThenID(_ a: SequenceItem, _ b: SequenceItem) -> Bool {
        (a.timeSeconds ?? Int64.min, a.id) < (b.timeSeconds ?? Int64.min, b.id)
    }

    private static func hamming(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }
}
