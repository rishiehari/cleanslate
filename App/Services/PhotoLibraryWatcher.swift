import Foundation
import Photos

/// PhotoKit notifications are an invalidation hint, not a durable event log.
/// The deletion coordinator always refetches and re-verifies independently.
final class PhotoLibraryWatcher: NSObject, PHPhotoLibraryChangeObserver {
    var onChange: (() -> Void)?
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }
}
