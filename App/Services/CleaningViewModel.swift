import Foundation
import Photos
import Combine
import CryptoKit
import CleanSlateCore

@MainActor
final class CleaningViewModel: ObservableObject {
    @Published private(set) var authorization: PHAuthorizationStatus
    @Published private(set) var phase: ScanPhase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var groups: [PhotoReviewGroup] = []
    @Published private(set) var statistics = ScanStatistics()
    @Published var statusMessage: String?
    @Published private(set) var isScanning = false

    let library: PhotoLibraryClient
    private let coordinator: PhotoDeletionCoordinator
    let tray: DeletionTray
    let networkPolicy: NetworkPolicy
    private let featureStore = LocalFeatureIndex()
    private var scanTask: Task<Void, Never>?
    private var changeSubscription: ChangeSubscription?
    private var scanLimit = 1500

    init(library: PhotoLibraryClient = PhotoKitLibraryClient.shared,
         tray: DeletionTray? = nil,
         networkPolicy: NetworkPolicy? = nil) {
        self.library = library
        self.networkPolicy = networkPolicy ?? NetworkPolicy.shared
        self.tray = tray ?? DeletionTray(fileURL: DeletionTray.defaultURL())
        self.coordinator = PhotoDeletionCoordinator(library: library)
        self.authorization = library.authorization
        changeSubscription = library.observeChanges { [weak self] in
            self?.invalidateAfterLibraryChange()
        }
    }

    func refreshPermissions() {
        let newStatus = library.authorization
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

    func groups(in category: ScanCategory) -> [PhotoReviewGroup] {
        guard let kind = category.groupKind else { return [] }
        return groups.filter { $0.kind == kind }
    }

    func verifiedBytes(in category: ScanCategory) -> Int64 {
        groups(in: category).reduce(Int64(0)) { $0 + $1.estimatedVerifiedBytes }
    }

    #if DEBUG
    /// UI tests and screenshots only: show prepared groups without running a scan.
    func seedGroupsForUITesting(_ seeded: [PhotoReviewGroup]) {
        groups = seeded
        phase = .finished
        progress = 1
    }
    #endif

    var potentialVerifiedBytes: Int64 {
        groups.reduce(Int64(0)) { $0 + $1.estimatedVerifiedBytes }
    }

    func requestPermission() {
        Task { authorization = await library.requestAccess() }
    }

    /// Upper bound of assets fully hashed in one scan (the rest are reported as skipped).
    static let maximumFullHashesPerScan = 4_000

    /// Rough size guess used only to budget iCloud downloads.
    static func estimatedOriginalBytes(_ photo: PhotoSnapshot?) -> Int64 {
        guard let photo else { return 0 }
        if photo.isVideo { return Int64(photo.durationSeconds * 2_000_000) }
        return max(2_000_000, photo.pixelCount / 4)
    }

    /// Stable across launches (unlike `hashValue`), so reviewed groups and the tray survive relaunch.
    static func stableToken(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Runs one scan to completion. `scan()` wraps this in a cancellable task; tests await it directly.
    func runScan() async {
        guard !isScanning, authorization == .authorized || authorization == .limited else { return }
        isScanning = true
        statistics = ScanStatistics(); statusMessage = nil; groups = []; progress = 0
        networkPolicy.resetSessionBudget()          // the iCloud download limit is per scan
        await performScan()
        isScanning = false
    }

    func scan() {
        guard !isScanning else { return }
        scanTask = Task { [weak self] in
            await self?.runScan()
            self?.scanTask = nil
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

    /// Deletes everything in the tray (after the user confirmed in the summary sheet).
    /// Each group is still fully revalidated by the coordinator, and Apple shows its own prompt.
    func deleteTray() async {
        let idsBefore = Set(tray.entries.map(\.id))
        let receipt = await tray.deleteAll(using: coordinator)
        let deleted = idsBefore.subtracting(tray.entries.map(\.id))
        groups.removeAll { deleted.contains($0.id) }
        if receipt.verifiedRemoved > 0 { HapticsService.shared.fire(.batchDeleted) }
    }

    private func performScan() async {
        phase = .inventory
        let listing = library.inventory(limit: scanLimit)
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
            } else if let thumbnail = await library.thumbnail(photo.id, target: 280),
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

        // Exact stage. Candidates come from cheap metadata buckets plus the best visual pairs;
        // only those are hashed in full. Every resource of every asset is hashed (Live Photos,
        // edits and RAW included); anything that can't be read completely is NOT a match.
        phase = .fullResources
        let buckets = ExactCandidates.buckets(photos.map { photo in
            ExactKey(id: photo.id, mediaType: photo.isVideo ? 2 : 1, pixelWidth: photo.width, pixelHeight: photo.height,
                     creationSecond: photo.capturedAt.map { Int64($0.timeIntervalSince1970) },
                     durationMillis: Int64(photo.durationSeconds * 1000), originalFilename: photo.originalFilename)
        })
        statistics.exactBucketsFound = buckets.buckets.count
        statistics.bucketsOversized = buckets.oversizedBuckets
        // Smaller buckets first (most likely real copies), then the best visual pairs. A cap keeps one
        // scan bounded; anything past it is reported, not silently skipped.
        var orderedIDs: [String] = []
        var queued: Set<String> = []
        func enqueue(_ id: String) { if queued.insert(id).inserted { orderedIDs.append(id) } }
        buckets.buckets.sorted { $0.count < $1.count }.forEach { $0.forEach(enqueue) }
        candidatePairs.forEach { enqueue($0.first); enqueue($0.second) }
        if orderedIDs.count > Self.maximumFullHashesPerScan {
            statistics.exactSkippedByLimit = orderedIDs.count - Self.maximumFullHashesPerScan
            orderedIDs = Array(orderedIDs.prefix(Self.maximumFullHashesPerScan))
        }
        var allDigests: [String: [ResourceDigest]] = [:]
        let fetcher = DigestFetcher(library: library, policy: networkPolicy)
        for (n, id) in orderedIDs.enumerated() {
            if Task.isCancelled { phase = .cancelled; return }
            guard byID[id] != nil else { continue }
            do {
                let result = try await fetcher.fetch(id: id, estimatedBytes: Self.estimatedOriginalBytes(byID[id]))
                allDigests[id] = result.digests
                statistics.exactAssetsHashed += 1
                if result.downloaded { statistics.originalsDownloaded += 1 }
            } catch is CancellationError {
                phase = .cancelled; return
            } catch LibraryResourceError.cancelled {
                phase = .cancelled; return
            } catch {
                // Not local (iCloud), incomplete or failed: cannot claim a match.
                statistics.exactAssetsUnverifiable += 1
            }
            if n % 5 == 0 { progress = 0.65 + 0.23 * Double(n + 1) / Double(max(1, orderedIDs.count)); await Task.yield() }
        }
        if Task.isCancelled { phase = .cancelled; return }

        var groupsFound: [PhotoReviewGroup] = []
        var claimedIDs: Set<String> = []
        let identified = Dictionary(grouping: allDigests.compactMap { id, digests -> (String, String)? in
            guard let signature = ResourceSignatures.canonical(digests) else { return nil }
            return (signature, id)
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
            let group = PhotoReviewGroup(id: "exact-\(Self.stableToken(signature))", kind: .exact,
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
            guard let firstImage = await library.thumbnail(a.id, target: 512),
                  let secondImage = await library.thumbnail(b.id, target: 512) else { continue }
            let distance: Double
            do {
                let firstPrint = try await VisualFeatures.printFeature(firstImage)
                let secondPrint = try await VisualFeatures.printFeature(secondImage)
                distance = try VisualFeatures.distance(firstPrint, secondPrint)
            } catch {
                statistics.visionFailures += 1
                continue
            }
            guard distance < 0.32 else { continue }
            let (sharpA, exposeA) = VisualFeatures.sharpnessAndExposure(firstImage)
            let (sharpB, exposeB) = VisualFeatures.sharpnessAndExposure(secondImage)
            let qa = QualitySignals(id: a.id, sharpness: sharpA,
                                    faceQuality: (try? await VisualFeatures.faceQuality(firstImage)) ?? nil,
                                    aesthetics: try? await VisualFeatures.aesthetics(firstImage), exposure: exposeA,
                                    pixelCount: a.pixelCount, isFavorite: a.record.flags.contains(.favorite))
            let qb = QualitySignals(id: b.id, sharpness: sharpB,
                                    faceQuality: (try? await VisualFeatures.faceQuality(secondImage)) ?? nil,
                                    aesthetics: try? await VisualFeatures.aesthetics(secondImage), exposure: exposeB,
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
            guard let keeper = library.snapshot(id: group.keeper.id, inspectAlbums: true) else { return nil }
            let candidates = group.candidates.compactMap { item in
                library.snapshot(id: item.id, inspectAlbums: true)
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
        if statistics.visionFailures > 0 {
            statusMessage = (statusMessage ?? "") + " Similar-photo comparison was unavailable for \(statistics.visionFailures) pair(s) on this device."
        }
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
