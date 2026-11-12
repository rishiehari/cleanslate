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

    /// One page of the library (images and videos), newest first. Callers walk pages instead of
    /// holding the whole library in memory.
    func inventoryPage(offset: Int, limit: Int) -> (photos: [PhotoSnapshot], total: Int)
    /// Bounded metadata-only overview, without resource enumeration or thumbnail requests.
    func activitySummary() async throws -> PhotoActivitySummary
    /// Scan-only async inventory. Production applies bounds in PhotoKit and reads metadata off-main.
    func scanInventoryPage(offset: Int, limit: Int, request: ScanInventoryRequest) async throws -> ScanInventoryPage
    /// Opaque archived token for "now" (used to catch up on changes later), or nil if unsupported.
    func currentChangeToken() -> Data?
    /// What changed since `token`. `.tokenExpired` means the history is gone: do a full inventory.
    func changes(since token: Data) -> LibraryChangeResult
    /// Fresh snapshot of one asset, or nil if it no longer exists / is not accessible.
    func snapshot(id: String, inspectAlbums: Bool) -> PhotoSnapshot?
    /// Local-only thumbnail; nil when no local rendition exists.
    func thumbnail(_ id: String, target: CGFloat) async -> UIImage?
    /// Bounded, local-only hints for the next few review photos. Empty ids release the hints.
    func prefetchThumbnails(_ ids: [String], target: CGFloat)
    /// Digest of EVERY resource of the asset. Reads the network only when `allowNetwork` is true,
    /// which only `NetworkPolicy` (via `DigestFetcher`) may request.
    func digests(id: String, allowNetwork: Bool) async throws -> [ResourceDigest]
    /// Size in bytes of the asset's local file(s), or nil if not local. Never touches the network
    /// and never uses private API (videos: the local file's size; images: the streamed resource bytes).
    func verifiedSize(id: String) async -> Int64?
    /// Identifiers of every asset that sits in one of the user's own albums (one pass, no per-asset lookups).
    func userAlbumAssetIDs() -> Set<String>
    /// Album membership for THESE ids only (targeted lookup; no whole-library pass).
    func albumMemberIDs(among ids: [String]) async -> Set<String>
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
    func prefetchThumbnails(_ ids: [String], target: CGFloat) {}
    /// Local-only convenience.
    func digests(id: String) async throws -> [ResourceDigest] { try await digests(id: id, allowNetwork: false) }
}

struct LibraryChangeSet: Sendable, Equatable {
    var changedIDs: Set<String>        // inserted or updated assets
    var deletedIDs: Set<String>
    var newToken: Data?
}

enum LibraryChangeResult: Sendable, Equatable {
    case changes(LibraryChangeSet)
    case tokenExpired
    case unavailable
}

enum LibraryResourceError: LocalizedError, Equatable {
    case notAccessible, changed, empty, cancelled, timedOut
    var errorDescription: String? {
        switch self {
        case .notAccessible: "Original not available locally. No bytes were verified."
        case .changed: "Photo changed during verification."
        case .empty: "Photo has no accessible resources."
        case .cancelled: "Resource scan was cancelled."
        case .timedOut: "Timed out while reading the photo. It was not checked."
        }
    }
}

/// Views get the library from the environment; nil means "use the real PhotoKit client".
private struct PhotoLibraryKey: EnvironmentKey {
    static var defaultValue: PhotoLibraryClient? { nil }
}

extension EnvironmentValues {
    var photoLibraryOverride: PhotoLibraryClient? {
        get { self[PhotoLibraryKey.self] }
        set { self[PhotoLibraryKey.self] = newValue }
    }
}
