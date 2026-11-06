import Foundation
import Photos
import Combine
import CleanSlateCore

@MainActor
final class CleaningViewModel: ObservableObject {
    @Published private(set) var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var phase: ScanPhase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var groups: [PhotoReviewGroup] = []
    @Published private(set) var statistics = ScanStatistics()
    @Published var statusMessage: String?
    @Published var isDeleting = false
    @Published private(set) var isScanning = false
    @Published var deletionReceipt: String?

    private let catalog = PhotoCatalog.shared
    private let featureStore = LocalFeatureIndex()
    private let libraryWatcher = PhotoLibraryWatcher()
    private var scanTask: Task<Void, Never>?
    private var scanLimit = 1500

    init() {
        libraryWatcher.onChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.invalidateAfterLibraryChange()
            }
        }
        PHPhotoLibrary.shared().register(libraryWatcher)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(libraryWatcher)
    }

    func refreshPermissions() {
        let newStatus = catalog.authorization
        if newStatus != authorization {
            scanTask?.cancel()
            groups = []
            statusMessage = "Photos access changed. Please scan again."
        }
        authorization = newStatus
    }

    private func invalidateAfterLibraryChange() {
        // Invalidation is conservative. A late notification can arrive after a completed
        // scan, so the user must rescan rather than trusting stale recommendations.
        if isScanning { scanTask?.cancel() }
        if !groups.isEmpty {
            groups = []
            statusMessage = "The Photos library changed. Previous matches were invalidated. Scan again."
        }
    }

    var potentialVerifiedBytes: Int64 {
        groups.reduce(Int64(0)) { $0 + $1.estimatedVerifiedBytes }
    }

    func requestPermission() {
        Task { authorization = await catalog.requestAccess() }
    }

    func scan() {
        guard !isScanning, authorization == .authorized || authorization == .limited else { return }
        isScanning = true
        statistics = ScanStatistics(); statusMessage = nil; groups = []; progress = 0
        scanTask = Task { [weak self] in
            await self?.performScan()
            self?.scanTask = nil
            self?.isScanning = false
        }
    }

    func scanMore() {
        scanLimit = min(25_000, scanLimit * 2)
        scan()
    }

    func stop() { scanTask?.cancel() }

    func clearIndex() {
        guard !isScanning else { return }
        featureStore.clear()
        groups = []
        statistics = ScanStatistics()
        statusMessage = "The local feature cache was cleared. Photos were not modified."
    }

    func delete(group: PhotoReviewGroup, selected: Set<String>, manuallyReviewed: Set<String>) async -> Bool {
        guard !isDeleting else { return false }
        isDeleting = true
        defer { isDeleting = false }
        do {
            let receipt = try await PhotoDeletionCoordinator.shared.commit(
                group: group, selected: selected, manuallyReviewed: manuallyReviewed)
            deletionReceipt = "Requested \(receipt.requested) deletion(s). Verified removed: \(receipt.verifiedRemoved). "
                + "Verified logical bytes: \(receipt.logicalBytesRemoved.friendlyBytes). "
                + "Uncertain: \(receipt.uncertain). Check Photos and Recently Deleted."
            groups.removeAll { $0.id == group.id }
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    private func performScan() async {
        phase = .inventory
        let listing = catalog.inventory(limit: scanLimit)
        let photos = listing.photos
        statistics.photosEnumerated = photos.count
        statistics.truncated = listing.totalVisible > photos.count
        if photos.isEmpty { phase = .finished; progress = 1; return }

        var hashes: [String: UInt64] = [:]
        hashes.reserveCapacity(photos.count)
        phase = .thumbnails
        for (n, photo) in photos.enumerated() {
            if Task.isCancelled { phase = .cancelled; return }
            if let cached = featureStore.hash(for: photo.id, revision: photo.record.revision) {
                hashes[photo.id] = cached
            } else if let thumbnail = await catalog.thumbnail(photo.id),
                      let hash = VisualFeatures.differenceHash(thumbnail) {
                hashes[photo.id] = hash
                featureStore.put(hash, for: photo.id, revision: photo.record.revision)
            } else {
                statistics.cloudOnlyOrUnavailable += 1
            }
            statistics.thumbnailsAnalyzed = n + 1
            if n % 20 == 0 { progress = 0.65 * Double(n + 1) / Double(photos.count); await Task.yield() }
        }

        if Task.isCancelled { phase = .cancelled; return }
        phase = .candidates
        let byID = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        let items = photos.map { photo in
            IndexedPhoto(id: photo.id,
                         capturedAtSeconds: photo.capturedAt.map { Int64($0.timeIntervalSince1970) },
                         burstIdentifier: photo.burstID,
                         differenceHash: hashes[photo.id])
        }
        let allPairs = CandidateIndex.propose(items, maximumPairs: 75_000)
        // A bounded preview pass. The UI explicitly discloses this is not an exhaustive
        // proof of no duplicates, especially for photos with no local thumbnail.
        let rankedPairs = allPairs.sorted { a,b in
            func rank(_ p: CandidatePair) -> (Int, Int, String) {
                let left = byID[p.first], right = byID[p.second]
                let sameBurst = left?.burstID != nil && left?.burstID == right?.burstID
                let hamming = hashes[p.first].flatMap { x in hashes[p.second].map { CandidateIndex.hamming(x, $0) } } ?? 64
                return (sameBurst ? 0 : 1, hamming, p.first + p.second)
            }
            let x = rank(a), y = rank(b)
            if x.0 != y.0 { return x.0 < y.0 }
            if x.1 != y.1 { return x.1 < y.1 }
            return x.2 < y.2
        }
        let candidatePairs = Array(rankedPairs.prefix(240))
        statistics.candidatePairsConsidered = candidatePairs.count
        phase = .fullResources
        let candidateIDs = Set(candidatePairs.flatMap { [$0.first, $0.second] })
        var allDigests: [String: [ResourceDigest]] = [:]
        let orderedIDs = candidateIDs.sorted()
        for (n,id) in orderedIDs.enumerated() {
            if Task.isCancelled { phase = .cancelled; return }
            // Restrict large-resource hashing to relatively simple photos. An asset with
            // an unavailable original is NOT a verified exact duplicate.
            guard let photo = byID[id], photo.record.flags.isDisjoint(with: [.livePhoto,.raw,.edited,.shared]),
                  let asset = catalog.fetchAsset(id) else { continue }
            do {
                allDigests[id] = try await catalog.completeDigests(asset)
                statistics.exactAssetsVerified += 1
            } catch { /* Local-only asset or permission failure: do not claim a match. */ }
            if n % 5 == 0 { progress = 0.65 + 0.23 * Double(n + 1) / Double(max(1, orderedIDs.count)); await Task.yield() }
        }
        if Task.isCancelled { phase = .cancelled; return }

        var groupsFound: [PhotoReviewGroup] = []
        var claimedIDs: Set<String> = []
        let identified = Dictionary(grouping: allDigests.compactMap { id,digests -> (String, String)? in
            guard let signature = ResourceSignatures.canonical(digests) else { return nil }
            return (signature,id)
        }, by: { $0.0 })
        for (signature, members) in identified.sorted(by: { $0.key < $1.key }) where members.count > 1 {
            let snapshots = members.compactMap { byID[$0.1] }
            let keeper = preferredKeeper(snapshots)
            let remaining = snapshots.filter { $0.id != keeper.id }
            guard !remaining.isEmpty else { continue }
            let pairEvidence = remaining.map {
                PairEvidence(first: keeper.id, second: $0.id,
                             relation: .exactResources, completeResourceEquality: true)
            }
            let bytes = Dictionary(uniqueKeysWithValues: remaining.compactMap { photo -> (String, Int64)? in
                guard let digest = allDigests[photo.id], let size = ResourceSignatures.logicalBytes(digest) else { return nil }
                return (photo.id, size)
            })
            let group = PhotoReviewGroup(id: "exact-\(signature.hashValue)-\(keeper.id)", kind: .exact,
                                         keeper: keeper, candidates: remaining, evidence: pairEvidence,
                                         verifiedCandidateBytes: bytes)
            groupsFound.append(group)
            claimedIDs.formUnion(snapshots.map(\.id))
        }

        phase = .vision
        // Similarity is uncalibrated, so it is strictly manual-review only. Pairwise
        // groups prevent the transitive A~B, B~C => A~C deletion bug.
        for (n,pair) in candidatePairs.enumerated() {
            if Task.isCancelled { phase = .cancelled; return }
            if claimedIDs.contains(pair.first) || claimedIDs.contains(pair.second) { continue }
            guard let a = byID[pair.first], let b = byID[pair.second],
                  let ah = hashes[a.id], let bh = hashes[b.id],
                  CandidateIndex.hamming(ah, bh) <= 10 else { continue }
            guard let firstImage = await catalog.thumbnail(a.id, target: 512),
                  let secondImage = await catalog.thumbnail(b.id, target: 512),
                  let firstPrint = VisualFeatures.printFeature(firstImage),
                  let secondPrint = VisualFeatures.printFeature(secondImage),
                  let distance = VisualFeatures.distance(firstPrint, secondPrint),
                  distance < 0.32 else { continue }
            let (sharpA, exposeA) = VisualFeatures.sharpnessAndExposure(firstImage)
            let (sharpB, exposeB) = VisualFeatures.sharpnessAndExposure(secondImage)
            let qa = QualitySignals(id: a.id, sharpness: sharpA,
                                    faceQuality: VisualFeatures.faceQuality(firstImage),
                                    aesthetics: VisualFeatures.aesthetics(firstImage), exposure: exposeA,
                                    pixelCount: a.pixelCount, isFavorite: a.record.flags.contains(.favorite))
            let qb = QualitySignals(id: b.id, sharpness: sharpB,
                                    faceQuality: VisualFeatures.faceQuality(secondImage),
                                    aesthetics: VisualFeatures.aesthetics(secondImage), exposure: exposeB,
                                    pixelCount: b.pixelCount, isFavorite: b.record.flags.contains(.favorite))
            let bestID = KeeperRanker.sorted([qa,qb]).first?.id ?? a.id
            let keeper = bestID == a.id ? a : b
            let candidate = bestID == a.id ? b : a
            groupsFound.append(PhotoReviewGroup(id: "near-\(n)-\(keeper.id)", kind: .similar,
                                               keeper: keeper, candidates: [candidate],
                                               evidence: [PairEvidence(first: keeper.id, second: candidate.id,
                                                                        relation: .visuallySimilar)],
                                               verifiedCandidateBytes: [:]))
            claimedIDs.insert(keeper.id); claimedIDs.insert(candidate.id)
            if groupsFound.count >= 150 { break }
            if n % 10 == 0 { progress = 0.88 + 0.1 * Double(n + 1) / Double(max(1,candidatePairs.count)); await Task.yield() }
        }
        // Review snapshots include the more expensive curated-album protection check.
        groups = groupsFound.compactMap { group -> PhotoReviewGroup? in
            guard let asset = catalog.fetchAsset(group.keeper.id) else { return nil }
            let keeper = catalog.snapshot(asset, inspectAlbums: true)
            let candidates = group.candidates.compactMap { item -> PhotoSnapshot? in
                guard let asset = catalog.fetchAsset(item.id) else { return nil }
                return catalog.snapshot(asset, inspectAlbums: true)
            }
            guard candidates.count == group.candidates.count else { return nil }
            return PhotoReviewGroup(id: group.id, kind: group.kind, keeper: keeper,
                                    candidates: candidates, evidence: group.evidence,
                                    verifiedCandidateBytes: group.verifiedCandidateBytes)
        }.sorted {
            $0.kind == $1.kind ? $0.estimatedVerifiedBytes > $1.estimatedVerifiedBytes : $0.kind == .exact
        }
        phase = .finished; progress = 1
        statusMessage = statistics.truncated
            ? "Partial scan: \(photos.count) of \(listing.totalVisible) accessible photos inventoried. "
              + "Only \(candidatePairs.count) candidate pairs verified/reviewed in this pass. Tap Scan More for broader coverage."
            : "Scanned \(photos.count) accessible photos. Not all iCloud-only originals were available locally; matches may be missed."
    }

    private func preferredKeeper(_ photos: [PhotoSnapshot]) -> PhotoSnapshot {
        // Preserve protected captures preferentially (favorite, user-picked, edited, RAW).
        let ranked = photos.sorted { a,b in
            let ap = a.record.flags.isEmpty ? 0 : 1
            let bp = b.record.flags.isEmpty ? 0 : 1
            if ap != bp { return ap > bp }
            if a.pixelCount != b.pixelCount { return a.pixelCount > b.pixelCount }
            return a.id < b.id
        }
        return ranked[0]
    }
}
