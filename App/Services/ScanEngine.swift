import Foundation
import CryptoKit
import UIKit
import os
import CleanSlateCore

/// A decoded thumbnail is immutable once created, so handing it to a background task is safe.
private struct ImageBox: @unchecked Sendable { let image: UIImage }

private enum VisionError: Error { case unavailable }

/// Small LRU cache (newest at the end). The engine is main-actor, so no locking is needed.
private struct LRUCache<Key: Hashable, Value> {
    private var storage: [Key: Value] = [:]
    private var order: [Key] = []            // oldest first
    let capacity: Int
    init(capacity: Int) { self.capacity = max(1, capacity) }
    func value(for key: Key) -> Value? {
        guard storage[key] != nil else { return nil }
        return storage[key]
    }
    mutating func insert(_ value: Value, for key: Key) {
        storage[key] = value
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity { storage[order.removeFirst()] = nil }
    }
}

@MainActor
protocol ScanReporting: AnyObject {
    func scanDidEnter(_ phase: ScanPhase)
    func scanProgress(_ value: Double)
    func scanUpdate(_ change: (inout ScanStatistics) -> Void)
    func scanFound(groups: [PhotoReviewGroup])
    func scanFoundStandalone(_ items: [StandaloneItem], albumMembers: Set<String>)
}

/// The resumable scan: sync the library into the store (full or incremental), fingerprint images in
/// batches, find candidates with cheap queries, then verify. Everything expensive is checkpointed in
/// the store, so a killed or paused scan continues instead of restarting.
@MainActor
final class ScanEngine {
    enum Outcome: Equatable { case finished, cancelled, stopped(reason: String) }

    static let featureVersion = 2
    static let pageSize = 1_000
    static let maximumFullHashesPerScan = 4_000
    static let maximumSizedItems = 5_000
    /// Upper bound on similar-photo pairs examined with Vision in one pass (reported when reached).
    static let maximumVisionPairs = 30_000
    static let maximumCandidatePairs = 200_000
    /// This many Vision failures in a row means it is unavailable on this device.
    static let visionFailureLimit = 5

    private let library: PhotoLibraryClient
    private let store: LibraryStore
    private let networkPolicy: NetworkPolicy
    private let governor: ResourceGovernor
    private let visual: VisualAnalyzing
    private let limits: ScanLimits
    weak var reporter: ScanReporting?
    /// Local diagnostics (nil = off). Counts, durations and phase names only; never photo information.
    var diagnostics: DiagnosticsLog?
    /// Per-request Vision deadline (docs/features/F03): an abandoned request is a Vision failure, never a match.
    nonisolated static let visionTimeout: TimeInterval = 10
    /// One feature print per asset per scan; 64 entries by spec.
    private var printCache = LRUCache<String, VisualPrint>(capacity: 64)
    /// One quality pass per asset per scan, shared by review sets and similar pairs; 2,000 entries by spec.
    private var qualityCache = LRUCache<String, QualitySignals>(capacity: 2_000)
    /// Lock-protected live counters, owned by the view model and shared with the heartbeat/watchdog.
    let counters: ScanCounters
    private var phaseStartedAt: ContinuousClock.Instant?
    private var signpost: OSSignpostIntervalState?
    private var libraryItems = 0
    private var lastTickBucket = -1
    /// Set by `skipCurrentStage()`; the next phase checkpoint ends the current phase early
    /// (recorded in statistics.stagesSkipped). Skipping never marks anything as matched.
    private var skipRequested = false

    init(library: PhotoLibraryClient, store: LibraryStore, networkPolicy: NetworkPolicy, governor: ResourceGovernor,
         visual: VisualAnalyzing = VisionVisualAnalyzer(), counters: ScanCounters = ScanCounters(),
         limits: ScanLimits = ScanLimits()) {
        self.library = library; self.store = store; self.networkPolicy = networkPolicy; self.governor = governor
        self.visual = visual; self.counters = counters; self.limits = limits
    }

    // MARK: Entry point

    func run() async -> Outcome {
        counters.reset(); libraryItems = 0; lastTickBucket = -1
        let outcome = await runPhases()
        endPhase()
        // Leave the counters in an honest resting state for the watchdog's phase attribution.
        counters.update { $0.phase = outcome == .finished ? .finished : .idle; $0.inFlight = 0 }
        // Any outcome means the run ended on its own; only a killed process leaves the marker behind.
        await ScanInProgressMarker.clear(in: store)
        return outcome
    }

    /// Ends the current stage at its next checkpoint and moves on to the next phase.
    func skipCurrentStage() { skipRequested = true }

    /// Consumes a pending skip request for `phase`; returns true when the phase must end now.
    private func shouldSkip(_ phase: ScanPhase) -> Bool {
        guard skipRequested else { return false }
        skipRequested = false
        reporter?.scanUpdate { $0.stagesSkipped.append(phase) }
        return true
    }

    // MARK: Diagnostics hooks (all no-ops when `diagnostics` is nil)

    /// Announces a stage to the UI, the log, Instruments and the "scan in progress" marker.
    private func enter(_ phase: ScanPhase) async {
        endPhase()
        reporter?.scanDidEnter(phase)
        let diag = DiagPhase(phase)
        counters.update { $0 = ScanCounters.Snapshot(phase: diag, total: $0.total, thumbsTried: $0.thumbsTried, thumbsUnavailable: $0.thumbsUnavailable) }
        lastTickBucket = -1
        phaseStartedAt = .now
        signpost = ScanSignposts.begin(diag)
        diagnostics?.record(.phaseEntered(phase: diag, units: libraryItems))
        await ScanInProgressMarker.set(diag, in: store)
    }

    private func endPhase() {
        guard let started = phaseStartedAt else { return }
        let s = counters.snapshot
        let elapsed = started.duration(to: .now)
        let millis = Int(elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
        diagnostics?.record(.phaseEnded(phase: s.phase, millis: millis, done: s.done, total: s.total))
        if s.phase == .thumbnails, s.thumbsTried > 0 {
            diagnostics?.record(.thumbnailStats(tried: s.thumbsTried, unavailable: s.thumbsUnavailable, unavailablePercent: s.thumbnailUnavailablePercent))
        }
        if let signpost { ScanSignposts.end(signpost) }
        signpost = nil; phaseStartedAt = nil
    }

    /// Progress inside a stage: always updates the live counters, and logs once per 25 items.
    /// `inFlight` is managed separately at the request sites, so an honest count survives between ticks.
    private func tick(done: Int, total: Int) {
        counters.update { $0.done = done; $0.total = total }
        let bucket = done / 25
        if bucket != lastTickBucket {
            lastTickBucket = bucket
            diagnostics?.record(.progress(phase: counters.snapshot.phase, done: done, total: total))
        }
    }

    private func runPhases() async -> Outcome {
        guard let reporter else { return .cancelled }
        await enter(.inventory)
        await syncInventory()
        if Task.isCancelled { return .cancelled }
        let total = await store.assetCount()
        reporter.scanUpdate { $0.photosEnumerated = total }
        diagnostics?.record(.scanStarted(scope: .all, items: total))
        if total == 0 { return .finished }
        libraryItems = total

        await enter(.thumbnails)
        if let early = await computeFeatures() { return early }

        await enter(.candidates)
        reporter.scanProgress(0.60)
        let buckets = ExactCandidates.buckets(await store.exactKeys())
        reporter.scanUpdate { $0.exactBucketsFound = buckets.buckets.count; $0.bucketsOversized = buckets.oversizedBuckets }
        let pairs = await rankedNearPairs()
        if Task.isCancelled { return .cancelled }
        reporter.scanUpdate { $0.candidatePairsConsidered = pairs.count }

        await enter(.fullResources)
        var claimed: Set<String> = []
        if let early = await verifyExactCopies(buckets: buckets, pairs: pairs, claimed: &claimed) { return early }

        await enter(.sizing)
        if let early = await findStandaloneItems() { return early }

        await enter(.vision)
        if let early = await buildReviewSets(claimed: &claimed) { return early }
        if let early = await compareSimilarPairs(pairs, claimed: &claimed) { return early }
        reporter.scanProgress(1)
        return .finished
    }

    // MARK: 1. Inventory sync

    private typealias Meta = LibrarySync.Meta

    private func syncInventory() async {
        if await store.meta(Meta.complete) != nil, let token = await store.meta(Meta.token), await store.assetCount() > 0 {
            switch library.changes(since: token) {
            case .changes(let set):
                await applyChanges(set)
                reporter?.scanUpdate { $0.inventoryMode = .incremental }
                return
            case .tokenExpired:
                reporter?.scanUpdate { $0.tokenExpired = true }
            case .unavailable:
                break
            }
        }
        await fullInventory()
    }

    private func applyChanges(_ set: LibraryChangeSet) async {
        let touched = await LibrarySync.apply(set, library: library, store: store)
        reporter?.scanUpdate { $0.changesApplied = touched }
    }

    private func fullInventory() async {
        var offset = 0
        var startedAt = Date().timeIntervalSince1970
        // Resume an interrupted full inventory instead of starting over.
        if await store.meta(Meta.complete) == nil,
           let savedOffset = await store.meta(Meta.offset).flatMap({ String(data: $0, encoding: .utf8) }).flatMap(Int.init),
           let savedStart = await store.meta(Meta.startedAt).flatMap({ String(data: $0, encoding: .utf8) }).flatMap(Double.init) {
            offset = savedOffset; startedAt = savedStart
            reporter?.scanUpdate { $0.inventoryMode = .resumed }
        } else {
            try? await store.setMeta(Meta.complete, nil)
            try? await store.setMeta(Meta.startedAt, Data(String(startedAt).utf8))
            try? await store.setMeta(Meta.startToken, library.currentChangeToken())
            reporter?.scanUpdate { $0.inventoryMode = .full }
        }
        while true {
            if Task.isCancelled || shouldSkip(.inventory) { return }
            let page = library.inventoryPage(offset: offset, limit: Self.pageSize)
            if page.photos.isEmpty { break }
            try? await store.upsert(page.photos)
            offset += page.photos.count
            try? await store.setMeta(Meta.offset, Data(String(offset).utf8))
            reporter?.scanProgress(0.10 * Double(offset) / Double(max(1, page.total)))
            tick(done: offset, total: page.total)
            await Task.yield()
            if offset >= page.total { break }
        }
        if Task.isCancelled { return }
        _ = try? await store.markUnseen(before: startedAt)
        try? await store.setMeta(Meta.token, await store.meta(Meta.startToken))
        try? await store.setMeta(Meta.offset, nil)
        try? await store.setMeta(Meta.complete, Data([1]))
    }

    // MARK: 2. Fingerprints (resumable: every batch is committed)

    private func computeFeatures() async -> Outcome? {
        try? await store.clearUnavailableFeatures()
        let pending = await store.pendingFeatureCount(version: Self.featureVersion)
        var processed = 0
        var cursor: Int64 = 0
        while true {
            if Task.isCancelled { return .cancelled }
            if shouldSkip(.thumbnails) { return nil }
            switch await governor.checkpoint() {
            case .stop(let reason): return .stopped(reason: reason)
            case .proceed: break      // width is clamped by ScanLimits.maxInFlight (one asset at a time)
            }
            let next = await store.imageAssetsNeedingFeatures(afterRowID: cursor, limit: limits.featurePage, version: Self.featureVersion)
            let batch = next.photos
            if batch.isEmpty { break }
            cursor = next.lastRowID
            var hashed: [(id: String, revision: String, dhash: UInt64)] = []
            var unavailable: [(id: String, revision: String)] = []
            var pendingSinceCommit = 0
            var pageHashed = 0, pageUnavailable = 0
            func commitIfDue(force: Bool = false) async {
                guard pendingSinceCommit > 0, (force || pendingSinceCommit >= governor.batchSize) else { return }
                try? await store.putFeatures(hashed, version: Self.featureVersion)
                try? await store.markFeaturesUnavailable(unavailable)
                hashed.removeAll(keepingCapacity: true); unavailable.removeAll(keepingCapacity: true)
                pendingSinceCommit = 0
            }
            // Strictly one asset in flight (F03): per-asset autoreleasepool via a detached hash task,
            // no task group of main-actor children.
            for photo in batch {
                if Task.isCancelled { break }
                counters.update { $0.inFlight = 1 }
                let image = await library.thumbnail(photo.id, target: limits.fingerprintSide)
                counters.update { $0.inFlight = 0 }
                if let image {
                    let box = ImageBox(image: image)
                    let hash = await Task.detached(priority: .utility) { autoreleasepool { VisualFeatures.differenceHash(box.image) } }.value
                    if let hash {
                        hashed.append((photo.id, photo.record.revision, hash))
                        pageHashed += 1
                        counters.update { $0.thumbsTried += 1 }
                    } else {
                        unavailable.append((photo.id, photo.record.revision))
                        pageUnavailable += 1
                        counters.update { $0.thumbsTried += 1; $0.thumbsUnavailable += 1 }
                    }
                } else {
                    unavailable.append((photo.id, photo.record.revision))
                    pageUnavailable += 1
                    counters.update { $0.thumbsTried += 1; $0.thumbsUnavailable += 1 }
                }
                tick(done: processed + pageHashed + pageUnavailable, total: pending)
                pendingSinceCommit += 1
                await commitIfDue()                 // every governor.batchSize within the page
            }
            await commitIfDue(force: true)
            processed += pageHashed + pageUnavailable
            let done = processed
            reporter?.scanUpdate { $0.thumbnailsAnalyzed += pageHashed; $0.cloudOnlyOrUnavailable += pageUnavailable }
            reporter?.scanProgress(0.10 + 0.50 * Double(done) / Double(max(1, pending)))
            if Task.isCancelled { return .cancelled }
            await Task.yield()
        }
        return nil
    }

    // MARK: 3. Candidates

    /// Near-duplicate candidate pairs from LSH bands plus same-moment pairs, filtered by hash distance and
    /// ranked: bursts first, then closest hashes. Only proposals; nothing here proves similarity.
    /// The assembly (union/filter/rank) runs in detached utility tasks over Sendable values only.
    private func rankedNearPairs() async -> [CandidatePair] {
        if shouldSkip(.candidates) { return [] }
        let near = await store.nearHashPairs(maxHamming: 10, maximumBucketSize: 256, maximumPairs: limits.candidatePairCap)
        let moments = await store.momentPairs(maxSecondsApart: 12, maximumBucketSize: limits.momentBucketCap,
                                              maximumPairs: limits.candidatePairCap)
        reporter?.scanUpdate { $0.lshBucketsSkipped = near.skippedBuckets }
        let members = Array(Set(near.pairs.flatMap { [$0.first, $0.second] } + moments.flatMap { [$0.first, $0.second] }))
        let hashes = await store.dhashes(ids: members, version: Self.featureVersion)
        // Union + Hamming filter off the main actor; pure Sendable data crosses (no self, no snapshots).
        let close = await Task.detached(priority: .utility) {
            Array(Set(near.pairs).union(moments)).filter { pair in
                guard let a = hashes[pair.first], let b = hashes[pair.second] else { return false }
                return CandidateIndex.hamming(a, b) <= 10
            }
        }.value
        let burstIDs = await store.burstIDs(among: close.flatMap { [$0.first, $0.second] })
        // Sorting up to the tier cap of pairs is pure computation: keep it off the main thread.
        return await Task.detached(priority: .utility) { Self.rank(close, hashes: hashes, burstIDs: burstIDs) }.value
    }

    /// The digest queue: exact-bucket members plus near pairs that are near-identical (Hamming <= 2)
    /// at the same pixel size. Pure and testable; `cap` is min(4,000, scopeCount).
    nonisolated static func enqueueDigestCandidates(buckets: ExactBuckets, pairs: [CandidatePair],
                                                    hashes: [String: UInt64], dimensions: [String: (width: Int, height: Int)],
                                                    cap: Int) -> [String] {
        var order: [String] = []
        var queued: Set<String> = []
        func enqueue(_ id: String) { if queued.insert(id).inserted { order.append(id) } }
        buckets.buckets.sorted { $0.count < $1.count }.forEach { $0.forEach(enqueue) }
        for pair in pairs {
            guard let a = hashes[pair.first], let b = hashes[pair.second], CandidateIndex.hamming(a, b) <= 2,
                  let da = dimensions[pair.first], let db = dimensions[pair.second],
                  da.width == db.width, da.height == db.height else { continue }
            enqueue(pair.first); enqueue(pair.second)
        }
        return cap < order.count ? Array(order.prefix(cap)) : order
    }

    /// Bursts first, then the closest hashes; ties broken by id so the order is deterministic.
    nonisolated static func rank(_ pairs: [CandidatePair], hashes: [String: UInt64], burstIDs: [String: String]) -> [CandidatePair] {
        func key(_ pair: CandidatePair) -> (Int, Int, String, String) {
            let sameBurst = burstIDs[pair.first] != nil && burstIDs[pair.first] == burstIDs[pair.second]
            return (sameBurst ? 0 : 1, CandidateIndex.hamming(hashes[pair.first] ?? 0, hashes[pair.second] ?? 0), pair.first, pair.second)
        }
        return pairs.sorted { key($0) < key($1) }
    }

    // MARK: 4. Exact copies

    private func verifyExactCopies(buckets: ExactBuckets, pairs: [CandidatePair], claimed: inout Set<String>) async -> Outcome? {
        // Smaller buckets first (most likely real copies), then the best visual pairs — narrowed to
        // pairs that are near-identical (Hamming <= 2) at the same pixel size (likely re-saved copies).
        // Capped per scan to min(4,000, scope); the rest is reported.
        let members = Array(Set(buckets.buckets.flatMap { $0 } + pairs.flatMap { [$0.first, $0.second] }))
        let hashes = await store.dhashes(ids: members, version: Self.featureVersion)
        let dimensions = await store.dimensions(among: members)
        let order = Self.enqueueDigestCandidates(buckets: buckets, pairs: pairs, hashes: hashes,
                                                 dimensions: dimensions, cap: min(Self.maximumFullHashesPerScan, max(libraryItems, 1)))
        if members.count > order.count {
            reporter?.scanUpdate { $0.exactSkippedByLimit = members.count - order.count }
        }
        let albums = await library.albumMemberIDs(among: order)
        let snapshots = await store.snapshots(ids: order)
        let fetcher = DigestFetcher(library: library, policy: networkPolicy)
        var digests: [String: [ResourceDigest]] = [:]
        for (n, id) in order.enumerated() {
            if Task.isCancelled { return .cancelled }
            if shouldSkip(.fullResources) { return nil }          // partial digests are never matched
            if case .stop(let reason) = await governor.checkpoint() { return .stopped(reason: reason) }
            guard let photo = snapshots[id] else { continue }
            counters.update { $0.inFlight = 1 }
            defer { counters.update { $0.inFlight = 0 } }
            do {
                let result = try await fetcher.fetch(id: id, estimatedBytes: Self.estimatedOriginalBytes(photo))
                digests[id] = result.digests
                reporter?.scanUpdate { $0.exactAssetsHashed += 1; if result.downloaded { $0.originalsDownloaded += 1 } }
            } catch is CancellationError {
                return .cancelled
            } catch LibraryResourceError.cancelled {
                return .cancelled
            } catch {
                reporter?.scanUpdate { $0.exactAssetsUnverifiable += 1 }   // not local, incomplete or failed: never a match
            }
            tick(done: n + 1, total: order.count)
            if n % 5 == 0 { reporter?.scanProgress(0.65 + 0.20 * Double(n + 1) / Double(max(1, order.count))); await Task.yield() }
        }
        let identified = Dictionary(grouping: digests.compactMap { id, items -> (String, String)? in
            ResourceSignatures.canonical(items).map { ($0, id) }
        }, by: { $0.0 })
        var found: [PhotoReviewGroup] = []
        for (signature, members) in identified.sorted(by: { $0.key < $1.key }) where members.count > 1 {
            let photos = members.compactMap { snapshots[$0.1] }.map { Self.markAlbum($0, albums) }
            let keeper = Self.preferredKeeper(photos)
            let remaining = photos.filter { $0.id != keeper.id }
            guard !remaining.isEmpty else { continue }
            let bytes = Dictionary(uniqueKeysWithValues: remaining.compactMap { photo -> (String, Int64)? in
                digests[photo.id].flatMap(ResourceSignatures.logicalBytes).map { (photo.id, $0) }
            })
            found.append(PhotoReviewGroup(
                id: "exact-\(Self.stableToken(signature))-\(Self.stableToken(photos.map(\.id).sorted().joined(separator: "|")))",
                kind: .exact, keeper: keeper, candidates: remaining,
                evidence: remaining.map { PairEvidence(first: keeper.id, second: $0.id, relation: .exactResources, completeResourceEquality: true) },
                verifiedCandidateBytes: bytes))
            claimed.formUnion(photos.map(\.id))
        }
        reporter?.scanFound(groups: found)
        return nil
    }

    // MARK: 5. Keeper-less lists

    private func findStandaloneItems() async -> Outcome? {
        let candidates = await store.standaloneCandidates(limit: Self.maximumSizedItems)
        let albums = await library.albumMemberIDs(among: candidates.map(\.id))
        var items: [StandaloneItem] = []
        for (n, photo) in candidates.enumerated() {
            if Task.isCancelled { return .cancelled }
            if shouldSkip(.sizing) { reporter?.scanFoundStandalone([], albumMembers: []); return nil }
            // Videos: size of the local file (no bytes read). Screenshots are measured when selected.
            counters.update { $0.inFlight = photo.isVideo ? 1 : 0 }
            defer { counters.update { $0.inFlight = 0 } }
            items.append(StandaloneItem(snapshot: photo, verifiedBytes: photo.isVideo ? await library.verifiedSize(id: photo.id) : nil))
            tick(done: n + 1, total: candidates.count)
            if n % 25 == 0 { reporter?.scanProgress(0.85 + 0.05 * Double(n + 1) / Double(max(1, candidates.count))); await Task.yield() }
        }
        reporter?.scanFoundStandalone(items, albumMembers: albums)
        return nil
    }

    /// Runs one Vision request under the 10 s deadline. Returns nil ONLY when the deadline expired
    /// (or the scan was cancelled) — that is recorded as .requestTimedOut and must be counted as a
    /// Vision failure by the caller, never a match. Throws the request's own error unchanged.
    private func visionCall<T: Sendable>(id: String, kind: DiagRequestKind,
                                         _ call: @escaping @MainActor () async throws -> T) async throws -> T? {
        let result = await Deadline.withDeadline(Self.visionTimeout, onExpire: {}) { (once: OneShotResume<Result<T, Error>>) in
            Task { @MainActor in
                do { once.resume(.success(try await call())) }
                catch { once.resume(.failure(error)) }
            }
        }
        guard let result else {
            diagnostics?.record(.requestTimedOut(kind: kind, asset: DiagnosticsLog.shared.salted(id), seconds: Int(Self.visionTimeout)))
            return nil
        }
        return try result.get()
    }

    /// Feature print for an asset, computed at most once per scan (LRU 64).
    private func featurePrint(for id: String, image: UIImage) async throws -> VisualPrint? {
        if let cached = printCache.value(for: id) { return cached }
        guard let print = try await visionCall(id: id, kind: .vision, { try await self.visual.featurePrint(image) }) else { return nil }
        printCache.insert(print, for: id)
        return print
    }

    /// Quality signals for an asset, computed at most once per scan (LRU 2,000), at `limits.visionSide`.
    /// Throws when a Vision call fails (the caller decides whether that disables Vision for the rest of the scan).
    private func quality(for photo: PhotoSnapshot, image: UIImage?, visionAllowed: Bool) async throws -> QualitySignals {
        if let cached = qualityCache.value(for: photo.id) { return cached }
        let signals: QualitySignals
        if let image {
            let (sharpness, exposure) = VisualFeatures.sharpnessAndExposure(image)
            var face: Double?, aesthetics: Double?
            if visionAllowed {
                // Under the 10 s deadline like every Vision request (edge finding M1): an expired
                // request throws -> the caller counts a Vision failure (never a match).
                guard let faceResult = try await visionCall(id: photo.id, kind: .vision,
                                                            { try await self.visual.faceQuality(image) }) else { throw VisionError.unavailable }
                face = faceResult
                guard let aestheticsResult = try await visionCall(id: photo.id, kind: .vision,
                                                                  { try await self.visual.aesthetics(image) }) else { throw VisionError.unavailable }
                aesthetics = aestheticsResult
            }
            signals = QualitySignals(id: photo.id, sharpness: sharpness, faceQuality: face, aesthetics: aesthetics, exposure: exposure,
                                     pixelCount: photo.pixelCount, isFavorite: photo.record.flags.contains(.favorite))
        } else {
            signals = QualitySignals(id: photo.id, pixelCount: photo.pixelCount, isFavorite: photo.record.flags.contains(.favorite))
        }
        qualityCache.insert(signals, for: photo.id)
        return signals
    }

    // MARK: 6a. Bursts and quick runs (review sets: several shots, you choose what to keep)

    private func buildReviewSets(claimed: inout Set<String>) async -> Outcome? {
        // Stream the sequence items through the grouping builder page by page (no whole-library array).
        var streamer = SequenceGrouping.Streamer()
        var afterTime: Int64? = nil
        var afterID = ""
        var fed = 0
        let totalImages = await store.imageAssetCount()
        while true {
            if Task.isCancelled { return .cancelled }
            if shouldSkip(.vision) { return nil }
            let page = await store.sequencePage(afterTime: afterTime, afterID: afterID, limit: 500, version: Self.featureVersion)
            if page.items.isEmpty { break }
            streamer.feed(page.items.filter { !claimed.contains($0.id) })
            fed += page.items.count
            afterTime = page.lastTime; afterID = page.lastID
            tick(done: fed, total: totalImages)
            await Task.yield()
        }
        let sets = streamer.finish()
        let albums = await library.albumMemberIDs(among: sets.flatMap { $0 })
        reporter?.scanUpdate { $0.reviewSetsFound = sets.count }
        var pending: [PhotoReviewGroup] = []
        var visionUsable = true
        for (n, ids) in sets.enumerated() {
            if Task.isCancelled { return .cancelled }
            if shouldSkip(.vision) { reporter?.scanFound(groups: []); return nil }
            if n % 10 == 0, case .stop(let reason) = await governor.checkpoint() { reporter?.scanFound(groups: pending); return .stopped(reason: reason) }
            let found = await store.snapshots(ids: ids)
            let photos = ids.compactMap { found[$0] }.map { Self.markAlbum($0, albums) }
            guard photos.count >= 2 else { continue }
            var quality: [QualitySignals] = []
            reporter?.scanUpdate { $0.visionReviewSetPhotos += photos.count }
            for photo in photos {
                counters.update { $0.inFlight = 1 }
                defer { counters.update { $0.inFlight = 0 } }
                let image = await library.thumbnail(photo.id, target: limits.visionSide)
                do {
                    quality.append(try await self.quality(for: photo, image: image, visionAllowed: visionUsable))
                } catch {
                    visionUsable = false
                    reporter?.scanUpdate { $0.visionFailures += 1; $0.visionUnavailable = true }
                    quality.append(QualitySignals(id: photo.id, pixelCount: photo.pixelCount, isFavorite: photo.record.flags.contains(.favorite)))
                }
            }
            let bestID = KeeperRanker.sorted(quality).first?.id ?? photos[0].id
            guard let keeper = photos.first(where: { $0.id == bestID }) else { continue }
            let rest = photos.filter { $0.id != keeper.id }
            // Evidence between EVERY pair, so whichever photos the user chooses to keep are directly linked to each one removed.
            var evidence: [PairEvidence] = []
            for (i, a) in photos.enumerated() { for b in photos[(i + 1)...] {
                evidence.append(PairEvidence(first: a.id, second: b.id, relation: .visuallySimilar))
            }}
            pending.append(PhotoReviewGroup(id: "seq-\(Self.stableToken(photos.map(\.id).sorted().joined(separator: "|")))", kind: .similar,
                                            keeper: keeper, candidates: rest, evidence: evidence, verifiedCandidateBytes: [:]))
            claimed.formUnion(photos.map(\.id))
            if pending.count >= 5 { reporter?.scanFound(groups: pending); pending = [] }
            tick(done: n + 1, total: sets.count)
            if n % 10 == 0 { reporter?.scanProgress(0.90 + 0.05 * Double(n + 1) / Double(max(1, sets.count))); await Task.yield() }
        }
        reporter?.scanFound(groups: pending)
        return nil
    }

    // MARK: 6b. Similar shots (Vision, manual review only)

    private func compareSimilarPairs(_ pairs: [CandidatePair], claimed: inout Set<String>) async -> Outcome? {
        // Similarity is uncalibrated, so it is strictly manual-review only. Pairwise groups prevent the
        // transitive A~B, B~C => A~C deletion bug.
        let limited = Array(pairs.prefix(limits.visionPairCap(scopeCount: libraryItems)))
        if pairs.count > limited.count { let skipped = pairs.count - limited.count; reporter?.scanUpdate { $0.visionPairsSkipped = skipped } }
        var pending: [PhotoReviewGroup] = []
        var pendingMembers: Set<String> = []
        var albums: Set<String> = []
        var consecutiveFailures = 0
        for (n, pair) in limited.enumerated() {
            if Task.isCancelled { return .cancelled }
            if shouldSkip(.vision) { reporter?.scanFound(groups: []); return nil }
            if n % 10 == 0, case .stop(let reason) = await governor.checkpoint() { reporter?.scanFound(groups: pending); return .stopped(reason: reason) }
            if claimed.contains(pair.first) || claimed.contains(pair.second) { continue }
            let both = await store.snapshots(ids: [pair.first, pair.second])
            guard let a = both[pair.first].map({ Self.markAlbum($0, albums) }), let b = both[pair.second].map({ Self.markAlbum($0, albums) }) else { continue }
            counters.update { $0.inFlight = 1 }
            defer { counters.update { $0.inFlight = 0 } }
            guard let firstImage = await library.thumbnail(a.id, target: limits.visionSide),
                  let secondImage = await library.thumbnail(b.id, target: limits.visionSide) else { continue }
            reporter?.scanUpdate { $0.visionPairsCompared += 1 }
            let distance: Double
            do {
                // Prints are cached per asset (LRU 64) and run under the per-request deadline;
                // an abandoned or failed request is a Vision failure, never a match.
                guard let firstPrint = try await featurePrint(for: a.id, image: firstImage),
                      let secondPrint = try await featurePrint(for: b.id, image: secondImage) else { throw VisionError.unavailable }
                distance = try firstPrint.distanceTo(secondPrint)
            } catch {
                reporter?.scanUpdate { $0.visionFailures += 1 }
                consecutiveFailures += 1
                // Vision isn't working here (e.g. no inference hardware): stop wasting time and battery on the rest.
                if consecutiveFailures >= Self.visionFailureLimit {
                    let skipped = limited.count - (n + 1)
                    reporter?.scanUpdate { $0.visionPairsSkipped += skipped; $0.visionUnavailable = true }
                    reporter?.scanFound(groups: pending)
                    return nil
                }
                continue
            }
            consecutiveFailures = 0
            guard distance < 0.32 else { continue }
            let qa = (try? await quality(for: a, image: firstImage, visionAllowed: true))
                ?? QualitySignals(id: a.id, pixelCount: a.pixelCount, isFavorite: a.record.flags.contains(.favorite))
            let qb = (try? await quality(for: b, image: secondImage, visionAllowed: true))
                ?? QualitySignals(id: b.id, pixelCount: b.pixelCount, isFavorite: b.record.flags.contains(.favorite))
            let bestID = KeeperRanker.sorted([qa, qb]).first?.id ?? a.id
            let keeper = bestID == a.id ? a : b
            let candidate = bestID == a.id ? b : a
            pending.append(PhotoReviewGroup(
                id: "near-\(Self.stableToken([a.id, b.id].sorted().joined(separator: "|")))", kind: .similar,
                keeper: keeper, candidates: [candidate],
                evidence: [PairEvidence(first: keeper.id, second: candidate.id, relation: .visuallySimilar)],
                verifiedCandidateBytes: [:]))
            claimed.insert(keeper.id); claimed.insert(candidate.id)
            pendingMembers.formUnion([keeper.id, candidate.id])
            if pending.count >= 5 {
                // Targeted album lookup for just the groups found in this batch (no whole-library pass).
                albums.formUnion(await library.albumMemberIDs(among: Array(pendingMembers)))
                reporter?.scanFound(groups: pending.map { group in
                    PhotoReviewGroup(id: group.id, kind: group.kind, keeper: Self.markAlbum(group.keeper, albums),
                                     candidates: group.candidates.map { Self.markAlbum($0, albums) },
                                     evidence: group.evidence, verifiedCandidateBytes: group.verifiedCandidateBytes)
                })
                pending = []; pendingMembers = []
            }
            tick(done: n + 1, total: limited.count)
            if n % 10 == 0 { reporter?.scanProgress(0.90 + 0.10 * Double(n + 1) / Double(max(1, limited.count))); await Task.yield() }
        }
        reporter?.scanFound(groups: pending)
        return nil
    }

    // MARK: Helpers

    static func stableToken(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func estimatedOriginalBytes(_ photo: PhotoSnapshot?) -> Int64 {
        guard let photo else { return 0 }
        if photo.isVideo { return Int64(photo.durationSeconds * 2_000_000) }
        return max(2_000_000, photo.pixelCount / 4)
    }

    /// Album membership comes from one set computed per scan, not per-asset PhotoKit lookups.
    static func markAlbum(_ photo: PhotoSnapshot, _ albums: Set<String>) -> PhotoSnapshot {
        guard albums.contains(photo.id), !photo.record.flags.contains(.curatedAlbum) else { return photo }
        var copy = photo
        copy.record = AssetRecord(id: photo.id, revision: photo.record.revision, flags: photo.record.flags.union([.curatedAlbum]),
                                  verifiedLogicalBytes: photo.record.verifiedLogicalBytes)
        return copy
    }

    /// Protected captures are preferred as keepers (favorite, user-picked, edited, RAW).
    static func preferredKeeper(_ photos: [PhotoSnapshot]) -> PhotoSnapshot {
        photos.sorted { a, b in
            let ap = a.record.flags.isEmpty ? 0 : 1, bp = b.record.flags.isEmpty ? 0 : 1
            if ap != bp { return ap > bp }
            if a.pixelCount != b.pixelCount { return a.pixelCount > b.pixelCount }
            return a.id < b.id
        }[0]
    }
}
