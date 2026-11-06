import Foundation
import Photos
import UIKit
import AVFoundation
import CryptoKit
import CleanSlateCore

/// All PhotoKit-facing work is isolated on the main actor. Inference and byte streaming use
/// asynchronous callbacks; the app does not call PhotoKit from an uncontrolled background task.
@MainActor
final class PhotoKitLibraryClient: PhotoLibraryClient {
    static let shared = PhotoKitLibraryClient()
    private let imageManager = PHCachingImageManager()
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
        if !registered { PHPhotoLibrary.shared().register(watcher); registered = true }
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

    func snapshot(id: String, inspectAlbums: Bool) -> PhotoSnapshot? {
        fetchAsset(id).map { snapshot($0, inspectAlbums: inspectAlbums) }
    }

    func digests(id: String, allowNetwork: Bool) async throws -> [ResourceDigest] {
        guard let asset = fetchAsset(id) else { throw LibraryResourceError.notAccessible }
        return try await completeDigests(asset, allowNetwork: allowNetwork)
    }

    func verifiedSize(id: String) async -> Int64? {
        guard let asset = fetchAsset(id) else { return nil }
        if asset.mediaType == .video {
            // The ORIGINAL file's size, read from its local URL (no bytes are read, no network).
            // Slo-mo / edited videos come back as a composition: size unknown (nil), never guessed.
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = false
            options.version = .original
            options.deliveryMode = .highQualityFormat
            return await withCheckedContinuation { (continuation: CheckedContinuation<Int64?, Never>) in
                let once = OneShot(continuation)
                PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                    // PhotoKit may call this more than once; only the first call may resume.
                    guard let url = (avAsset as? AVURLAsset)?.url,
                          let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                        once.resume(nil); return
                    }
                    once.resume(Int64(size))
                }
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

    func delete(ids: [String], expectedRevisions: [String: String]) async throws {
        let assets = ids.compactMap { fetchAsset($0) }
        guard assets.count == ids.count else { throw LibraryResourceError.notAccessible }
        // Re-read the exact objects handed to PhotoKit; abort if any differ from what the user approved.
        for asset in assets {
            guard let expected = expectedRevisions[asset.localIdentifier],
                  snapshot(asset).record.revision == expected else { throw LibraryResourceError.changed }
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    var authorization: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }

    func requestAccess() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    func inventory(limit: Int) -> (photos: [PhotoSnapshot], totalVisible: Int) {
        let opts = PHFetchOptions()
        opts.includeAllBurstAssets = true
        opts.includeHiddenAssets = false
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                     PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        let result = PHAsset.fetchAssets(with: opts)
        let count = min(result.count, limit)
        var photos: [PhotoSnapshot] = []
        photos.reserveCapacity(count)
        for index in 0..<count {
            let asset = result.object(at: index)
            photos.append(snapshot(asset))
        }
        return (photos, result.count)
    }

    private func fetchAsset(_ id: String) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        return result.firstObject
    }

    private func snapshot(_ asset: PHAsset, inspectAlbums: Bool = false) -> PhotoSnapshot {
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

    /// A local-only thumbnail. May return nil when an optimized iCloud original is unavailable.
    func thumbnail(_ id: String, target: CGFloat = 280) async -> UIImage? {
        guard let asset = fetchAsset(id) else { return nil }
        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = false
        opts.deliveryMode = .fastFormat
        opts.resizeMode = .fast
        return await withCheckedContinuation { continuation in
            let once = OneShotImageContinuation(continuation)
            imageManager.requestImage(for: asset,
                                      targetSize: CGSize(width: target, height: target),
                                      contentMode: .aspectFit,
                                      options: opts) { image, _ in
                // PhotoKit callbacks can be repeated or arrive from arbitrary queues.
                // Only the first completion may resume the Swift continuation.
                once.resume(image)
            }
        }
    }

    /// Full resource hashes, network strictly disabled. No KVC private fileSize API.
    private func completeDigests(_ asset: PHAsset, allowNetwork: Bool) async throws -> [ResourceDigest] {
        let resources = PHAssetResource.assetResources(for: asset)
        guard !resources.isEmpty else { throw LibraryResourceError.empty }
        var digests: [ResourceDigest] = []
        for resource in resources {
            try Task.checkCancellation()
            let digest = try await digest(resource, allowNetwork: allowNetwork)
            digests.append(digest)
        }
        return digests
    }

    private func digest(_ resource: PHAssetResource, allowNetwork: Bool) async throws -> ResourceDigest {
        let accumulator = LockedSHA256()
        let resourceType = "\(resource.type.rawValue):\(resource.uniformTypeIdentifier)"
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = allowNetwork
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ResourceDigest, Error>) in
            PHAssetResourceManager.default().requestData(for: resource, options: options,
                dataReceivedHandler: { data in accumulator.update(data) },
                completionHandler: { error in
                    if let error { continuation.resume(throwing: error); return }
                    let result = accumulator.finish(type: resourceType)
                    continuation.resume(returning: result)
                }
            )
        }
    }
}

/// Serializes incremental SHA updates delivered by PhotoKit without buffering the photo.
private final class LockedSHA256 {
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

/// Resumes a continuation at most once (PhotoKit handlers can fire repeatedly).
private final class OneShot<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    init(_ continuation: CheckedContinuation<Value, Never>) { self.continuation = continuation }
    func resume(_ value: Value) {
        lock.lock(); let current = continuation; continuation = nil; lock.unlock()
        current?.resume(returning: value)
    }
}

private final class OneShotImageContinuation {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UIImage?, Never>?
    init(_ continuation: CheckedContinuation<UIImage?, Never>) { self.continuation = continuation }
    func resume(_ image: UIImage?) {
        lock.lock()
        let current = continuation
        continuation = nil
        lock.unlock()
        current?.resume(returning: image)
    }
}
