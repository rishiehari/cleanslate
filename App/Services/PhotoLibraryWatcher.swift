import Foundation
import Photos

/// PhotoKit notifications are an invalidation hint, not a durable event log.
/// The deletion coordinator always refetches and re-verifies independently.
/// PhotoKit calls this on an arbitrary queue, so the callback is lock-protected.
final class PhotoLibraryWatcher: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (PHChange) -> Void)?

    func setHandler(_ handler: (@Sendable (PHChange) -> Void)?) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        lock.lock(); let current = handler; lock.unlock()
        current?(changeInstance)
    }
}
