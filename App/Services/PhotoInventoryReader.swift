import Foundation
import Photos
import os
import CleanSlateCore

/// The serial queue owns the PhotoKit fetch and all inventory resource metadata reads.
/// A stuck synchronous PhotoKit call cannot be interrupted, but never blocks the main actor.
/// Deadline/cancellation returns control to the UI and prevents additional queued asset work.
final class PhotoInventoryReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.cleanslate.inventory", qos: .userInitiated)
    private var fetch: PHFetchResult<PHAsset>?
    private var lastRequest: ScanInventoryRequest?
    static let pageTimeout: TimeInterval = 10

    func activitySummary() async throws -> PhotoActivitySummary {
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        let result: PhotoActivitySummary? = await Deadline.withDeadline(Self.pageTimeout, onExpire: {
            cancelled.withLock { $0 = true }
        }) { once in
            self.queue.async {
                guard !cancelled.withLock({ $0 }) else { once.resume(nil); return }
                let options = PHFetchOptions()
                options.includeAllBurstAssets = true
                options.includeHiddenAssets = false
                options.fetchLimit = 5_000
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                    PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
                let assets = PHAsset.fetchAssets(with: options)
                var builder = PhotoActivityBuilder()
                for index in 0..<min(assets.count, 5_000) {
                    guard !cancelled.withLock({ $0 }) else { once.resume(nil); return }
                    autoreleasepool {
                        let asset = assets.object(at: index)
                        builder.add(date: asset.creationDate, isBurst: asset.burstIdentifier != nil)
                    }
                }
                once.resume(builder.finish())
            }
        }
        try Task.checkCancellation()
        guard let result else { throw LibraryResourceError.timedOut }
        return result
    }

    func page(offset: Int, limit: Int, request: ScanInventoryRequest) async throws -> ScanInventoryPage {
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        let result: ScanInventoryPage? = await Deadline.withDeadline(Self.pageTimeout, onExpire: {
            cancelled.withLock { $0 = true }
        }) { once in
            self.queue.async {
                guard !cancelled.withLock({ $0 }) else { once.resume(nil); return }
                if offset == 0 || self.fetch == nil || self.lastRequest != request {
                    let options = PHFetchOptions()
                    options.includeAllBurstAssets = true
                    options.includeHiddenAssets = false
                    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                    var predicates = [NSPredicate(format: "mediaType == %d OR mediaType == %d",
                        PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)]
                    if let start = request.earliestDate {
                        predicates.append(NSPredicate(format: "creationDate >= %@", start as NSDate))
                    }
                    if let end = request.latestDate {
                        predicates.append(NSPredicate(format: "creationDate <= %@", end as NSDate))
                    }
                    options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                    if let cap = request.maximumItems { options.fetchLimit = cap }
                    self.fetch = PHAsset.fetchAssets(with: options)
                    self.lastRequest = request
                }
                guard let fetch = self.fetch else { once.resume(nil); return }
                let total = min(fetch.count, request.maximumItems ?? fetch.count)
                let upper = min(total, offset + max(0, limit))
                var photos: [PhotoSnapshot] = []
                if offset < upper {
                    for index in offset..<upper {
                        guard !cancelled.withLock({ $0 }) else { once.resume(nil); return }
                        let photo = autoreleasepool {
                            PhotoKitLibraryClient.makeSnapshot(fetch.object(at: index))
                        }
                        photos.append(photo)
                    }
                }
                once.resume(ScanInventoryPage(photos: photos, total: total))
            }
        }
        try Task.checkCancellation()
        guard let result else { throw LibraryResourceError.timedOut }
        return result
    }
}
