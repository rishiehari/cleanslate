import Foundation
import Photos
import SwiftUI
import UIKit
import CleanSlateCore

/// Everything the scan and deletion code needs from the Photos library. Production uses
/// `PhotoKitLibraryClient`; tests use `FakePhotoLibrary`. All members are main-actor
/// isolated, matching the current PhotoKit usage (revisited in Step 5 with Swift 6).
@MainActor
protocol PhotoLibraryClient: AnyObject {
    var authorization: PHAuthorizationStatus { get }
    func requestAccess() async -> PHAuthorizationStatus

    /// Newest-first inventory of image assets, capped at `limit`.
    func inventory(limit: Int) -> (photos: [PhotoSnapshot], totalVisible: Int)
    /// Fresh snapshot of one asset, or nil if it no longer exists / is not accessible.
    func snapshot(id: String, inspectAlbums: Bool) -> PhotoSnapshot?
    /// Local-only thumbnail; nil when no local rendition exists.
    func thumbnail(_ id: String, target: CGFloat) async -> UIImage?
    /// Digest of EVERY resource of the asset. Never touches the network.
    func digests(id: String) async throws -> [ResourceDigest]
    /// Asks the system to delete the assets. The system presents its own confirmation.
    /// Throws if the user cancels or the change fails.
    func delete(ids: [String]) async throws

    /// Invalidation hint only; observers must refetch and re-verify.
    func startObservingChanges(_ onChange: @escaping @MainActor () -> Void)
    func stopObservingChanges()
}

enum LibraryResourceError: LocalizedError {
    case notAccessible, changed, empty, cancelled
    var errorDescription: String? {
        switch self {
        case .notAccessible: "Original not available locally. No bytes were verified."
        case .changed: "Photo changed during verification."
        case .empty: "Photo has no accessible resources."
        case .cancelled: "Resource scan was cancelled."
        }
    }
}

private struct PhotoLibraryKey: EnvironmentKey {
    @MainActor static var defaultValue: PhotoLibraryClient { PhotoKitLibraryClient.shared }
}

extension EnvironmentValues {
    var photoLibrary: PhotoLibraryClient {
        get { self[PhotoLibraryKey.self] }
        set { self[PhotoLibraryKey.self] = newValue }
    }
}
