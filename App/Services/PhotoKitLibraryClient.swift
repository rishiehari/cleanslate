import Foundation
import Photos
import UIKit
import AVFoundation
import CryptoKit
import CleanSlateCore

/// UI, review and mutation operations are main-actor owned. Scan inventory and activity
/// metadata have a dedicated serial reader; no PhotoKit objects cross that queue.
@MainActor
final class PhotoKitLibraryClient: PhotoLibraryClient {
    static let shared = PhotoKitLibraryClient()
    private static let resourceQueue = DispatchQueue(label: "org.cleanslate.resource-watchdog", qos: .userInitiated)
    private let inventoryReader = PhotoInventoryReader()
    private let imageManager = PHCachingImageManager()
    private var prefetchedAssets: [PHAsset] = []
    private var prefetchTarget: CGFloat = 600
    private let watcher = PhotoLibraryWatcher()
    private var handlers: [UUID: @MainActor () -> Void] = [:]
    private var registered = false
    private init() {
        watcher.setHandler { [weak self] _ in
            Task { @MainActor in self?.handlers.values.forEach { $0() } }
        }
    }

    func observeChanges(_ onChange: @escaping @MainActor () -> Void) -> ChangeSubscription {
        let id = UUID()
        handlers[id] = onChange
        registerWatcherIfAuthorized()
        return ChangeSubscription { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.handlers[id] = nil
                if self.handlers.isEmpty && self.registered {
                    PHPhotoLibrary.shared().unregisterChangeObserver(self.watcher)
                    self.registered = false
                }
            }
        }
    }

    private func registerWatcherIfAuthorized() {
        guard !registered, !handlers.isEmpty, authorization == .authorized || authorization == .limited else { return }
        PHPhotoLibrary.shared().register(watcher)
        registered = true
    }

    func snapshot(id: String, inspectAlbums: Bool) -> PhotoSnapshot? {
        fetchAsset(id).map { snapshot($0, inspectAlbums: inspectAlbums) }
    }

    func digests(id: String, allowNetwork: Bool) async throws -> [ResourceDigest] {
        guard let asset = fetchAsset(id) else { throw LibraryResourceError.notAccessible }
        return try await completeDigests(asset, allowNetwork: allowNetwork)
    }

    /// The ORIGINAL file's size: a hard deadline (videos), or the streamed-bytes path below (images),
    /// which carries the digest inactivity watchdog (20 s, reset per chunk).
    nonisolated static let sizeTimeout: TimeInterval = 10
    /// Local-only thumbnail deadline: a PhotoKit callback that never fires must not outlive this.
    nonisolated static let thumbnailTimeout: TimeInterval = 10
    /// Digest inactivity deadline: reset on every data chunk (a slow-but-moving read is not dead).
    nonisolated static let digestInactivityTimeout: TimeInterval = 20

    func verifiedSize(id: String) async -> Int64? {
        guard let asset = fetchAsset(id) else { return nil }
        if asset.mediaType == .video {
            // The ORIGINAL file's size, read from its local URL (no bytes are read, no network).
            // Slo-mo / edited videos come back as a composition: size unknown (nil), never guessed.
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = false
            options.version = .original
            options.deliveryMode = .highQualityFormat
            let box = RequestIDBox()
            return await Deadline.withDeadline(Self.sizeTimeout, onExpire: {
                if let requestID = box.requestID {
                    Task { @MainActor in PHImageManager.default().cancelImageRequest(requestID) }
                }
                DiagnosticsLog.shared.record(.requestTimedOut(kind: .videoSize, asset: DiagnosticsLog.shared.salted(id),
                                                              seconds: Int(Self.sizeTimeout)))
            }) { (once: OneShotResume<Int64>) in
                let requestID = PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { @Sendable avAsset, _, _ in
                    // PhotoKit may call this more than once; only the first call may resume.
                    guard let url = (avAsset as? AVURLAsset)?.url,
                          let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                        once.resume(nil); return
                    }
                    once.resume(Int64(size))
                }
                box.set(requestID)
            }
        }
        guard let digests = try? await completeDigests(asset, allowNetwork: false) else { return nil }
        return ResourceSignatures.logicalBytes(digests)
    }

    func userAlbumAssetIDs() -> Set<String> {
        var ids: Set<String> = []
        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        albums.enumerateObjects { collection, _, _ in
            PHAsset.fetchAssets(in: collection, options: nil).enumerateObjects { asset, _, _ in ids.insert(asset.localIdentifier) }
        }
        return ids
    }

    /// Targeted album membership: only these ids are queried, and the loop yields every 50 assets.
    func albumMemberIDs(among ids: [String]) async -> Set<String> {
        var members: Set<String> = []
        for (index, id) in ids.enumerated() {
            guard let asset = fetchAsset(id) else { continue }
            if PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil).count > 0 {
                members.insert(id)
            }
            if index % 50 == 49 { await Task.yield() }
        }
        return members
    }

    func delete(ids: [String], expectedRevisions: [String: String]) async throws {
        let assets = ids.compactMap { fetchAsset($0) }
        guard assets.count == ids.count else { throw LibraryResourceError.notAccessible }
        // Re-read the exact objects handed to PhotoKit; abort if any differ from what the user approved.
        for asset in assets {
            guard let expected = expectedRevisions[asset.localIdentifier],
                  snapshot(asset).record.revision == expected else { throw LibraryResourceError.changed }
        }
        // Photos invokes the change block on an arbitrary serial queue: it must not be main-actor isolated
        // (Swift 6 would insert an executor check that traps there). PHAsset is not Sendable, but these
        // objects are only handed to PhotoKit, which owns them for the duration of the change block.
        nonisolated(unsafe) let approved = assets as NSArray
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            PHAssetChangeRequest.deleteAssets(approved)
        }
    }

    var authorization: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }

    func requestAccess() async -> PHAuthorizationStatus {
        let status = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { @Sendable status in
                continuation.resume(returning: status)
            }
        }
        registerWatcherIfAuthorized()
        return status
    }

    private var inventoryFetch: PHFetchResult<PHAsset>?

    func inventoryPage(offset: Int, limit: Int) -> (photos: [PhotoSnapshot], total: Int) {
        if offset == 0 || inventoryFetch == nil {
            let opts = PHFetchOptions()
            opts.includeAllBurstAssets = true
            opts.includeHiddenAssets = false
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            opts.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                         PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
            inventoryFetch = PHAsset.fetchAssets(with: opts)
        }
        guard let result = inventoryFetch else { return ([], 0) }
        var photos: [PhotoSnapshot] = []
        let upper = min(result.count, offset + limit)
        if offset < upper {
            photos.reserveCapacity(upper - offset)
            for index in offset..<upper {
                // Per-asset pool: no UIImage / CGImage outlives its iteration (bounded memory).
                autoreleasepool { photos.append(snapshot(result.object(at: index))) }
            }
        }
        return (photos, result.count)
    }

    func activitySummary() async throws -> PhotoActivitySummary {
        try await inventoryReader.activitySummary()
    }

    func scanInventoryPage(offset: Int, limit: Int, request: ScanInventoryRequest) async throws -> ScanInventoryPage {
        registerWatcherIfAuthorized()
        return try await inventoryReader.page(offset: offset, limit: limit, request: request)
    }

    func currentChangeToken() -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: PHPhotoLibrary.shared().currentChangeToken, requiringSecureCoding: true)
    }

    func changes(since tokenData: Data) -> LibraryChangeResult {
        guard let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: tokenData) else { return .unavailable }
        do {
            let fetch = try PHPhotoLibrary.shared().fetchPersistentChanges(since: token)
            var changed: Set<String> = [], deleted: Set<String> = []
            var latest = token
            for change in fetch {
                latest = change.changeToken
                guard let details = try? change.changeDetails(for: .asset) else { continue }
                changed.formUnion(details.insertedLocalIdentifiers); changed.formUnion(details.updatedLocalIdentifiers)
                deleted.formUnion(details.deletedLocalIdentifiers)
            }
            changed.subtract(deleted)
            let newToken = try? NSKeyedArchiver.archivedData(withRootObject: latest, requiringSecureCoding: true)
            return .changes(LibraryChangeSet(changedIDs: changed, deletedIDs: deleted, newToken: newToken))
        } catch let error as PHPhotosError where error.code == .persistentChangeTokenExpired {
            return .tokenExpired
        } catch {
            return .unavailable
        }
    }

    private func fetchAsset(_ id: String) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        return result.firstObject
    }

    private func snapshot(_ asset: PHAsset, inspectAlbums: Bool = false) -> PhotoSnapshot {
        Self.makeSnapshot(asset, inspectAlbums: inspectAlbums)
    }

    nonisolated static func makeSnapshot(_ asset: PHAsset, inspectAlbums: Bool = false) -> PhotoSnapshot {
        var flags: Set<PreservationFlag> = []
        if asset.isFavorite { flags.insert(.favorite) }
        if asset.isHidden { flags.insert(.hidden) }
        if asset.mediaSubtypes.contains(.photoLive) { flags.insert(.livePhoto) }
        if asset.burstSelectionTypes.contains(.userPick) { flags.insert(.userBurstPick) }
        if asset.sourceType.contains(.typeCloudShared) || asset.sourceType.contains(.typeiTunesSynced) {
            flags.insert(.shared)
        }
        // Expensive enough to reserve for actual review/commit candidates, not 250k
        // inventory records. Membership in a user-curated album is protected.
        if inspectAlbums && PHAssetCollection.fetchAssetCollectionsContaining(
            asset, with: .album, options: nil).count > 0 {
            flags.insert(.curatedAlbum)
        }
        if asset.mediaSubtypes.contains(.videoCinematic) { flags.insert(.cinematicVideo) }
        if asset.mediaSubtypes.contains(.spatialMedia) { flags.insert(.spatialMedia) }
        let resources = PHAssetResource.assetResources(for: asset)
        if resources.isEmpty { flags.insert(.incompleteResources) }
        if resources.contains(where: { $0.type == .adjustmentData || $0.type == .adjustmentBasePhoto }) {
            flags.insert(.edited)
        }
        if resources.contains(where: { resource in
            let ext = (resource.originalFilename as NSString).pathExtension.lowercased()
            return ["dng","arw","nef","cr2","cr3","raf","rw2","orf","pef"].contains(ext)
        }) { flags.insert(.raw) }
        let resourceIdentity = resources.map { "\($0.type.rawValue):\($0.originalFilename):\($0.uniformTypeIdentifier)" }.sorted().joined(separator: "^")
        // The full bytes of a candidate and its keeper are independently rehashed at commit.
        let state = [
            String(asset.creationDate?.timeIntervalSince1970 ?? -1),
            String(asset.modificationDate?.timeIntervalSince1970 ?? -1),
            String(asset.pixelWidth), String(asset.pixelHeight),
            String(asset.mediaSubtypes.rawValue),
            String(asset.burstSelectionTypes.rawValue),
            String(asset.isFavorite), String(asset.isHidden), resourceIdentity
        ].joined(separator: "|")
        let revision = SHA256.hash(data: Data(state.utf8)).map { String(format: "%02x", $0) }.joined()
        let record = AssetRecord(id: asset.localIdentifier, revision: revision, flags: flags)
        return PhotoSnapshot(id: asset.localIdentifier, record: record,
                             capturedAt: asset.creationDate, burstID: asset.burstIdentifier,
                             width: asset.pixelWidth, height: asset.pixelHeight,
                             originalFilename: resources.first(where: { $0.type == .photo || $0.type == .video })?.originalFilename,
                             isVideo: asset.mediaType == .video, durationSeconds: asset.duration,
                             subtypes: asset.mediaSubtypes.rawValue)
    }

    func prefetchThumbnails(_ ids: [String], target: CGFloat) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        imageManager.stopCachingImages(for: prefetchedAssets,
                                       targetSize: CGSize(width: prefetchTarget, height: prefetchTarget),
                                       contentMode: .aspectFit, options: options)
        prefetchedAssets = Array(ids.prefix(8)).compactMap { fetchAsset($0) }
        prefetchTarget = target
        imageManager.startCachingImages(for: prefetchedAssets, targetSize: CGSize(width: target, height: target),
                                        contentMode: .aspectFit, options: options)
    }

    /// A local-only thumbnail. May return nil when an optimized iCloud original is unavailable,
    /// and nil when the request outlives `thumbnailTimeout` (treated the same as "no local rendition").
    ///
    /// `.fastFormat` only succeeds when PhotoKit already holds a cached small derivative. Freshly imported,
    /// restored or synced items may not have one yet (PHPhotosErrorDomain 3303 "No resource found matching
    /// image request spec"), so a nil fast result that is neither cancelled nor cloud-only is retried ONCE with
    /// `.highQualityFormat` + `.fast` resize — still network-disabled and under its own deadline — which
    /// decodes a small rendition from the local original. Found on a real-photo simulator library (2026-11-12).
    func thumbnail(_ id: String, target: CGFloat = 280) async -> UIImage? {
        guard let asset = fetchAsset(id) else { return nil }
        let fast = await localImage(asset, id: id, target: target, mode: .fastFormat)
        if let image = fast.image { return image }
        guard fast.retryable, !Task.isCancelled else { return nil }
        return await localImage(asset, id: id, target: target, mode: .highQualityFormat).image
    }

    /// The one-time local retry is only for "no cached derivative": never after a cancellation, never for a
    /// cloud-only original (that would need the network), and never after a deadline (handled by the caller).
    nonisolated static func shouldRetryLocally(imageMissing: Bool, cancelled: Bool, inCloud: Bool) -> Bool {
        imageMissing && !cancelled && !inCloud
    }

    private struct LocalImageResult: Sendable {
        let image: UIImage?
        /// Nil result that is not a cancellation, timeout or cloud-only original.
        let retryable: Bool
    }

    private func localImage(_ asset: PHAsset, id: String, target: CGFloat, mode: PHImageRequestOptionsDeliveryMode) async -> LocalImageResult {
        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = false
        opts.deliveryMode = mode
        opts.resizeMode = .fast
        let box = RequestIDBox()
        let result = await Deadline.withDeadline(Self.thumbnailTimeout, onExpire: { [weak self] in
            if let requestID = box.requestID {
                Task { @MainActor in self?.imageManager.cancelImageRequest(requestID) }
            }
            DiagnosticsLog.shared.record(.requestTimedOut(kind: .thumbnail, asset: DiagnosticsLog.shared.salted(id),
                                                          seconds: Int(Self.thumbnailTimeout)))
        }) { (once: OneShotResume<LocalImageResult>) in
            let requestID = self.imageManager.requestImage(for: asset,
                                                           targetSize: CGSize(width: target, height: target),
                                                           contentMode: .aspectFit,
                                                           options: opts) { @Sendable image, info in
                // PhotoKit callbacks can be repeated or arrive from arbitrary queues.
                // Only the first completion may resume the Swift continuation.
                let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
                let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool) == true
                once.resume(LocalImageResult(image: image, retryable: Self.shouldRetryLocally(imageMissing: image == nil,
                                                                                         cancelled: cancelled, inCloud: inCloud)))
            }
            box.set(requestID)
        }
        return result ?? LocalImageResult(image: nil, retryable: false)   // deadline expired: never retried
    }

    /// Full resource hashes, network strictly disabled. No KVC private fileSize API.
    private func completeDigests(_ asset: PHAsset, allowNetwork: Bool) async throws -> [ResourceDigest] {
        let resources = PHAssetResource.assetResources(for: asset)
        guard !resources.isEmpty else { throw LibraryResourceError.empty }
        var digests: [ResourceDigest] = []
        for resource in resources {
            try Task.checkCancellation()
            let digest = try await digest(resource, assetID: asset.localIdentifier, allowNetwork: allowNetwork)
            digests.append(digest)
        }
        return digests
    }

    private func digest(_ resource: PHAssetResource, assetID: String, allowNetwork: Bool) async throws -> ResourceDigest {
        let accumulator = LockedSHA256()
        let resourceType = "\(resource.type.rawValue):\(resource.uniformTypeIdentifier)"
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = allowNetwork
        let box = DigestBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ResourceDigest, Error>) in
                let once = OneShotThrow(continuation)
                let watchdog = InactivityWatchdog()
                let timer = DispatchSource.makeTimerSource(queue: Self.resourceQueue)
                timer.schedule(deadline: .now() + 1, repeating: 1)
                timer.setEventHandler { @Sendable in
                    guard watchdog.inactive(for: Self.digestInactivityTimeout) else { return }
                    timer.cancel()
                    watchdog.cancelRequest()
                    DiagnosticsLog.shared.record(.requestTimedOut(kind: .digest,
                                                                  asset: DiagnosticsLog.shared.salted(assetID),
                                                                  seconds: Int(Self.digestInactivityTimeout)))
                    once.resume(throwing: LibraryResourceError.timedOut)
                }
                timer.resume()
                let requestID = PHAssetResourceManager.default().requestData(for: resource, options: options,
                    dataReceivedHandler: { @Sendable data in
                        watchdog.touch()                 // inactivity clock resets per chunk
                        accumulator.update(data)
                    },
                    completionHandler: { @Sendable error in
                        timer.cancel()
                        if let error { once.resume(throwing: error); return }
                        let result = accumulator.finish(type: resourceType)
                        once.resume(returning: result)
                    })
                watchdog.setRequestID(requestID)
                box.fill(once: once, watchdog: watchdog)
                // Cancellation may have arrived before the request even started.
                if Task.isCancelled {
                    watchdog.cancelRequest()
                    once.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            // Prompt: cancel the request AND resume now, so a completion handler that never
            // fires cannot hold the scan until the 20 s inactivity watchdog gives up.
            box.watchdog?.cancelRequest()
            box.resume?.resume(throwing: CancellationError())
        }
    }
}

/// Serializes incremental SHA updates delivered by PhotoKit without buffering the photo.
private final class LockedSHA256: @unchecked Sendable {   // NSLock-guarded
    private let lock = NSLock()
    private var context = SHA256()
    private var bytes: Int64 = 0
    func update(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        context.update(data: data)
        bytes += Int64(data.count)
    }
    func finish(type: String) -> ResourceDigest {
        lock.lock(); defer { lock.unlock() }
        let digest = context.finalize().map { String(format: "%02x", $0) }.joined()
        return ResourceDigest(type: type, byteCount: bytes, sha256: digest)
    }
}

/// Holds a PhotoKit request id set after the request starts, readable from the timeout closure.
private final class RequestIDBox: @unchecked Sendable {
    private let lock = NSLock()
    private var raw: PHImageRequestID?
    var requestID: PHImageRequestID? { lock.lock(); defer { lock.unlock() }; return raw }
    func set(_ id: PHImageRequestID) { lock.lock(); raw = id; lock.unlock() }
}

/// Shares the live digest request between the operation and the cancellation handler.
private final class DigestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var once: OneShotThrow<ResourceDigest>?
    private var inactivity: InactivityWatchdog?
    func fill(once: OneShotThrow<ResourceDigest>, watchdog: InactivityWatchdog) {
        lock.lock(); self.once = once; self.inactivity = watchdog; lock.unlock()
    }
    var resume: OneShotThrow<ResourceDigest>? { lock.lock(); defer { lock.unlock() }; return once }
    var watchdog: InactivityWatchdog? { lock.lock(); defer { lock.unlock() }; return inactivity }
}

/// Digest inactivity watchdog: the deadline resets on every data chunk; on expiry the request
/// itself is cancelled and `.timedOut` is thrown (fail-closed: "couldn't check", never a match).
private final class InactivityWatchdog: @unchecked Sendable {
    private let lock = NSLock()
    private var lastActivity = Date()
    private var requestID: PHAssetResourceDataRequestID?
    func touch() { lock.lock(); lastActivity = Date(); lock.unlock() }
    func inactive(for seconds: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return Date().timeIntervalSince(lastActivity) >= seconds
    }
    func setRequestID(_ id: PHAssetResourceDataRequestID) { lock.lock(); requestID = id; lock.unlock() }
    func cancelRequest() {
        lock.lock(); let id = requestID; lock.unlock()
        if let id { PHAssetResourceManager.default().cancelDataRequest(id) }
    }
}

/// Resumes a throwing continuation at most once.
private final class OneShotThrow<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }
    func resume(returning value: Value) {
        lock.lock(); let current = continuation; continuation = nil; lock.unlock()
        current?.resume(returning: value)
    }
    func resume(throwing error: Error) {
        lock.lock(); let current = continuation; continuation = nil; lock.unlock()
        current?.resume(throwing: error)
    }
}
