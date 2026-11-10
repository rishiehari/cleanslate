import Foundation
import CryptoKit
import UIKit
import CleanSlateCore

/// A decoded thumbnail is immutable once created, so handing it to a background task is safe.
private struct ImageBox: @unchecked Sendable { let image: UIImage }

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

    static let featureVersion = 1
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
    weak var reporter: ScanReporting?

    init(library: PhotoLibraryClient, store: LibraryStore, networkPolicy: NetworkPolicy, governor: ResourceGovernor,
         visual: VisualAnalyzing = VisionVisualAnalyzer()) {
        self.library = library; self.store = store; self.networkPolicy = networkPolicy; self.governor = governor
        self.visual = visual
    }

    // MARK: Entry point

    func run() async -> Outcome {
        guard let reporter else { return .cancelled }
        reporter.scanDidEnter(.inventory)
        await syncInventory()
        if Task.isCancelled { return .cancelled }
        let total = await store.assetCount()
        reporter.scanUpdate { $0.photosEnumerated = total }
        if total == 0 { return .finished }

        reporter.scanDidEnter(.thumbnails)
        if let early = await computeFeatures() { return early }

        reporter.scanDidEnter(.candidates)
        reporter.scanProgress(0.60)
        let buckets = ExactCandidates.buckets(await store.exactKeys())
        reporter.scanUpdate { $0.exactBucketsFound = buckets.buckets.count; $0.bucketsOversized = buckets.oversizedBuckets }
        let pairs = await rankedNearPairs()
        if Task.isCancelled { return .cancelled }
        reporter.scanUpdate { $0.candidatePairsConsidered = pairs.count }

        reporter.scanDidEnter(.fullResources)
        let albums = library.userAlbumAssetIDs()
        var claimed: Set<String> = []
        if let early = await verifyExactCopies(buckets: buckets, pairs: pairs, albums: albums, claimed: &claimed) { return early }

        reporter.scanDidEnter(.sizing)
        if let early = await findStandaloneItems(albums: albums) { return early }

        reporter.scanDidEnter(.vision)
        if let early = await buildReviewSets(albums: albums, claimed: &claimed) { return early }
        if let early = await compareSimilarPairs(pairs, albums: albums, claimed: &claimed) { return early }
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
            if Task.isCancelled { return }
            let page = library.inventoryPage(offset: offset, limit: Self.pageSize)
            if page.photos.isEmpty { break }
            try? await store.upsert(page.photos)
            offset += page.photos.count
            try? await store.setMeta(Meta.offset, Data(String(offset).utf8))
            reporter?.scanProgress(0.10 * Double(offset) / Double(max(1, page.total)))
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
            let concurrency: Int
            switch await governor.checkpoint() {
            case .stop(let reason): return .stopped(reason: reason)
            case .proceed(let width): concurrency = width
            }
            let next = await store.imageAssetsNeedingFeatures(afterRowID: cursor, limit: 200, version: Self.featureVersion)
            let batch = next.photos
            if batch.isEmpty { break }
            cursor = next.lastRowID
            var hashed: [(id: String, revision: String, dhash: UInt64)] = []
            var unavailable: [(id: String, revision: String)] = []
            var index = 0
            while index < batch.count {
                if Task.isCancelled { break }
                let slice = Array(batch[index..<min(index + concurrency, batch.count)])
                index += slice.count
                // The library is main-actor bound; every call below hops to the main actor, so sharing it is safe.
                nonisolated(unsafe) let sharedLibrary = library
                let results = await withTaskGroup(of: (PhotoSnapshot, UInt64?).self) { group -> [(PhotoSnapshot, UInt64?)] in
                    for photo in slice {
                        group.addTask { @MainActor in
                            guard let image = await sharedLibrary.thumbnail(photo.id, target: 280) else { return (photo, nil) }
                            let box = ImageBox(image: image)
                            let hash = await Task.detached(priority: .utility) { VisualFeatures.differenceHash(box.image) }.value
                            return (photo, hash)
                        }
                    }
                    var collected: [(PhotoSnapshot, UInt64?)] = []
                    for await item in group { collected.append(item) }
                    return collected
                }
                for (photo, hash) in results {
                    if let hash { hashed.append((photo.id, photo.record.revision, hash)) }
                    else { unavailable.append((photo.id, photo.record.revision)) }
                }
            }
            try? await store.putFeatures(hashed, version: Self.featureVersion)
            try? await store.markFeaturesUnavailable(unavailable)
            processed += hashed.count + unavailable.count
            let done = processed
            reporter?.scanUpdate { $0.thumbnailsAnalyzed += hashed.count; $0.cloudOnlyOrUnavailable += unavailable.count }
            reporter?.scanProgress(0.10 + 0.50 * Double(done) / Double(max(1, pending)))
            if Task.isCancelled { return .cancelled }
            await Task.yield()
        }
        return nil
    }

    // MARK: 3. Candidates

    /// Near-duplicate candidate pairs from LSH bands plus same-moment pairs, filtered by hash distance and
    /// ranked: bursts first, then closest hashes. Only proposals; nothing here proves similarity.
    private func rankedNearPairs() async -> [CandidatePair] {
        let near = await store.nearHashPairs(maxHamming: 10, maximumBucketSize: 256, maximumPairs: Self.maximumCandidatePairs)
        let moments = await store.momentPairs(maxSecondsApart: 12, maximumBucketSize: 256, maximumPairs: Self.maximumCandidatePairs)
        reporter?.scanUpdate { $0.lshBucketsSkipped = near.skippedBuckets }
        let all = Array(Set(near.pairs).union(moments))
        let hashes = await store.dhashes(ids: Array(Set(all.flatMap { [$0.first, $0.second] })))
        let close = all.filter { pair in
            guard let a = hashes[pair.first], let b = hashes[pair.second] else { return false }
            return CandidateIndex.hamming(a, b) <= 10
        }
        let burstIDs = await store.snapshots(ids: Array(Set(close.flatMap { [$0.first, $0.second] }))).compactMapValues(\.burstID)
        // Sorting up to 200k pairs is pure computation: keep it off the main thread.
        return await Task.detached(priority: .utility) { Self.rank(close, hashes: hashes, burstIDs: burstIDs) }.value
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

    private func verifyExactCopies(buckets: ExactBuckets, pairs: [CandidatePair], albums: Set<String>,
                                   claimed: inout Set<String>) async -> Outcome? {
        // Smaller buckets first (most likely real copies), then the best visual pairs. Capped per scan; the rest is reported.
        var order: [String] = []
        var queued: Set<String> = []
        func enqueue(_ id: String) { if queued.insert(id).inserted { order.append(id) } }
        buckets.buckets.sorted { $0.count < $1.count }.forEach { $0.forEach(enqueue) }
        pairs.forEach { enqueue($0.first); enqueue($0.second) }
        if order.count > Self.maximumFullHashesPerScan {
            let skipped = order.count - Self.maximumFullHashesPerScan
            reporter?.scanUpdate { $0.exactSkippedByLimit = skipped }
            order = Array(order.prefix(Self.maximumFullHashesPerScan))
        }
        let snapshots = await store.snapshots(ids: order)
        let fetcher = DigestFetcher(library: library, policy: networkPolicy)
        var digests: [String: [ResourceDigest]] = [:]
        for (n, id) in order.enumerated() {
            if Task.isCancelled { return .cancelled }
            if case .stop(let reason) = await governor.checkpoint() { return .stopped(reason: reason) }
            guard let photo = snapshots[id] else { continue }
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

    private func findStandaloneItems(albums: Set<String>) async -> Outcome? {
        let candidates = await store.standaloneCandidates(limit: Self.maximumSizedItems)
        var items: [StandaloneItem] = []
        for (n, photo) in candidates.enumerated() {
            if Task.isCancelled { return .cancelled }
            // Videos: size of the local file (no bytes read). Screenshots are measured when selected.
            items.append(StandaloneItem(snapshot: photo, verifiedBytes: photo.isVideo ? await library.verifiedSize(id: photo.id) : nil))
            if n % 25 == 0 { reporter?.scanProgress(0.85 + 0.05 * Double(n + 1) / Double(max(1, candidates.count))); await Task.yield() }
        }
        reporter?.scanFoundStandalone(items, albumMembers: albums)
        return nil
    }

    // MARK: 6a. Bursts and quick runs (review sets: several shots, you choose what to keep)

    private func buildReviewSets(albums: Set<String>, claimed: inout Set<String>) async -> Outcome? {
        let items = await store.sequenceItems().filter { !claimed.contains($0.id) }
        let sets = SequenceGrouping.groups(items)
        reporter?.scanUpdate { $0.reviewSetsFound = sets.count }
        var pending: [PhotoReviewGroup] = []
        var visionUsable = true
        for (n, ids) in sets.enumerated() {
            if Task.isCancelled { return .cancelled }
            if n % 10 == 0, case .stop(let reason) = await governor.checkpoint() { reporter?.scanFound(groups: pending); return .stopped(reason: reason) }
            let found = await store.snapshots(ids: ids)
            let photos = ids.compactMap { found[$0] }.map { Self.markAlbum($0, albums) }
            guard photos.count >= 2 else { continue }
            var quality: [QualitySignals] = []
            for photo in photos {
                guard let image = await library.thumbnail(photo.id, target: 512) else {
                    quality.append(QualitySignals(id: photo.id, pixelCount: photo.pixelCount, isFavorite: photo.record.flags.contains(.favorite))); continue
                }
                let (sharpness, exposure) = VisualFeatures.sharpnessAndExposure(image)
                var face: Double?, aesthetics: Double?
                if visionUsable {
                    do { face = try await visual.faceQuality(image); aesthetics = try await visual.aesthetics(image) }
                    catch { visionUsable = false; reporter?.scanUpdate { $0.visionFailures += 1; $0.visionUnavailable = true } }
                }
                quality.append(QualitySignals(id: photo.id, sharpness: sharpness, faceQuality: face, aesthetics: aesthetics, exposure: exposure,
                                              pixelCount: photo.pixelCount, isFavorite: photo.record.flags.contains(.favorite)))
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
            if n % 10 == 0 { reporter?.scanProgress(0.90 + 0.05 * Double(n + 1) / Double(max(1, sets.count))); await Task.yield() }
        }
        reporter?.scanFound(groups: pending)
        return nil
    }

    // MARK: 6b. Similar shots (Vision, manual review only)

    private func compareSimilarPairs(_ pairs: [CandidatePair], albums: Set<String>, claimed: inout Set<String>) async -> Outcome? {
        // Similarity is uncalibrated, so it is strictly manual-review only. Pairwise groups prevent the
        // transitive A~B, B~C => A~C deletion bug.
        let limited = Array(pairs.prefix(Self.maximumVisionPairs))
        if pairs.count > limited.count { let skipped = pairs.count - limited.count; reporter?.scanUpdate { $0.visionPairsSkipped = skipped } }
        var pending: [PhotoReviewGroup] = []
        var consecutiveFailures = 0
        for (n, pair) in limited.enumerated() {
            if Task.isCancelled { return .cancelled }
            if n % 10 == 0, case .stop(let reason) = await governor.checkpoint() { reporter?.scanFound(groups: pending); return .stopped(reason: reason) }
            if claimed.contains(pair.first) || claimed.contains(pair.second) { continue }
            let both = await store.snapshots(ids: [pair.first, pair.second])
            guard let a = both[pair.first].map({ Self.markAlbum($0, albums) }), let b = both[pair.second].map({ Self.markAlbum($0, albums) }) else { continue }
            guard let firstImage = await library.thumbnail(a.id, target: 512), let secondImage = await library.thumbnail(b.id, target: 512) else { continue }
            let distance: Double
            do {
                let firstPrint = try await visual.featurePrint(firstImage)
                let secondPrint = try await visual.featurePrint(secondImage)
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
            let (sharpA, exposeA) = VisualFeatures.sharpnessAndExposure(firstImage)
            let (sharpB, exposeB) = VisualFeatures.sharpnessAndExposure(secondImage)
            let qa = QualitySignals(id: a.id, sharpness: sharpA, faceQuality: (try? await visual.faceQuality(firstImage)) ?? nil,
                                    aesthetics: try? await visual.aesthetics(firstImage), exposure: exposeA,
                                    pixelCount: a.pixelCount, isFavorite: a.record.flags.contains(.favorite))
            let qb = QualitySignals(id: b.id, sharpness: sharpB, faceQuality: (try? await visual.faceQuality(secondImage)) ?? nil,
                                    aesthetics: try? await visual.aesthetics(secondImage), exposure: exposeB,
                                    pixelCount: b.pixelCount, isFavorite: b.record.flags.contains(.favorite))
            let bestID = KeeperRanker.sorted([qa, qb]).first?.id ?? a.id
            let keeper = bestID == a.id ? a : b
            let candidate = bestID == a.id ? b : a
            pending.append(PhotoReviewGroup(
                id: "near-\(Self.stableToken([a.id, b.id].sorted().joined(separator: "|")))", kind: .similar,
                keeper: keeper, candidates: [candidate],
                evidence: [PairEvidence(first: keeper.id, second: candidate.id, relation: .visuallySimilar)],
                verifiedCandidateBytes: [:]))
            claimed.insert(keeper.id); claimed.insert(candidate.id)
            if pending.count >= 5 { reporter?.scanFound(groups: pending); pending = [] }      // progressive results
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
