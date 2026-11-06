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
    /// Digest of EVERY resource of the asset. Reads the network only when `allowNetwork` is true,
    /// which only `NetworkPolicy` (via `DigestFetcher`) may request.
    func digests(id: String, allowNetwork: Bool) async throws -> [ResourceDigest]
    /// Asks the system to delete the assets. The system presents its own confirmation.
    /// Immediately before the change request, the implementation re-reads the very objects
    /// it is about to delete and throws `.changed` if any revision differs from
    /// `expectedRevisions`. Order of `ids` is not significant.
    /// Throws if the user cancels or the change fails.
    func delete(ids: [String], expectedRevisions: [String: String]) async throws

    /// Invalidation hint only; observers must refetch and re-verify. Keep the returned
    /// subscription alive for as long as you want callbacks; releasing it unsubscribes.
    func observeChanges(_ onChange: @escaping @MainActor () -> Void) -> ChangeSubscription
}

/// Unsubscribes when released.
final class ChangeSubscription {
    private let onCancel: () -> Void
    init(onCancel: @escaping () -> Void) { self.onCancel = onCancel }
    deinit { onCancel() }
}

extension PhotoLibraryClient {
    /// Local-only convenience.
    func digests(id: String) async throws -> [ResourceDigest] { try await digests(id: id, allowNetwork: false) }
}

enum LibraryResourceError: LocalizedError, Equatable {
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
