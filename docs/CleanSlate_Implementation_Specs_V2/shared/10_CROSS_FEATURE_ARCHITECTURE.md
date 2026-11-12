# Cross-feature architecture — buildable decomposition and ownership

## A. Module graph

```text
CleanSlate SwiftUI (universal iPhone + iPad)
   │
   ├─ iPhone Feature Screens              ├─ iPad Adaptive Feature Workspaces
   │                  \                    /
   │               Shared Feature View Models
   │                         │
   ├─ Safe Review Router ─────┘──────────────┐
   │                                         │
   ├─ New Feature Coordinators               │
   │    N05 Rules / N04 Plan / N07 Screenshots│
   │    N06 Quality / N01 Moment / N02 Video  │
   │    N03 Compress / N08 Albums / N09 Gems  │
   │    N10 Taste                            │
   │              │                          │
   │              ├──> LibraryStore (actor, 1 SQLite writer)
   │              ├──> PhotoLibraryClient (@MainActor PhotoKit gateway)
   │              ├──> ResourceGovernor (bounded compute)
   │              └──> CleanSlateCore (pure algorithms, SafetyPolicy)
   │                                         │
   └─────────────> Existing DeletionTray ────┴─> PhotoDeletionCoordinator
                                               │
                                               └─> single PhotoKit delete path
```

Do not wire the new view layer directly to `PHAssetChangeRequest.deleteAssets`; see the existing `PhotoDeletionCoordinator` and `PhotoLibraryClient` source. A universal binary can share domain services while owning separate presentation layouts by size class/window metrics. No extra backend/API or iPad-specific separate user store.

## B. New type families (proposals; reconcile with repo before compiling)

```swift
public struct ScopeDescriptor: Sendable, Codable {
  public let scopeID: String
  public let authorizedAccessibleItemCount: Int?
  public let sourceAuthorizationClass: String
  public let indexGeneration: Int64
  public let checkedItemCount: Int
  public let unavailableItemCount: Int
}

public enum EvidenceStatus: String, Sendable, Codable {
  case resourceVerified, visualCompared, reviewCandidate,
       unavailable, stale, unknown
}

public enum FeatureJobStatus: String, Sendable, Codable {
  case notStarted, running, paused, completed, partial, failed, stale
}

public struct FeatureCheckpoint: Sendable, Codable {
  public let featureID: String
  public let scopeID: String
  public let indexGeneration: Int64
  public let algorithmVersion: Int
  public let status: FeatureJobStatus
  public let processedCount: Int
  public let unknownCount: Int
  public let opaqueCursor: Data?
}

@MainActor
public protocol FeaturePhotoGateway {
  func authorizationSnapshot() -> PhotoAuthorizationScope
  func readPage(scope: ScopeDescriptor, cursor: Data?, maxCount: Int) -> [PhotoSnapshot]
  func readThumbnail(id: String, maxAxisPixels: Int) async -> UIImage?
  func freshSnapshot(id: String, inspectAlbums: Bool) -> PhotoSnapshot?
}
```

Do not blindly add these proposed declarations to `CleanSlateCore`: `PhotoSnapshot` and `UIImage` currently belong to the app target, so the `FeaturePhotoGateway` should live in `App/Services` and use app-level visibility. The pure `Core` models must instead contain primitive typed records and no UIKit/Photos imports. This note is deliberately explicit to stop an agent from making an impossible module dependency.

## C. Cancellation and actor boundary

PhotoKit callbacks/authorization remain on main-actor client as currently written, but CPU/ML work moves to an isolated bounded worker behind `Sendable` value DTOs. Do **not** pass mutable `UIImage` across threads unguarded; convert to an immutable bitmap buffer or an appropriately owned CGImage wrapper under a documented concurrency model and ensure it is released after one iteration. A worker receives `AnalysisBudget(maxFrames, maxWallSeconds, maxMemoryBytes)` and can return `partial` with a cursor. Every asset/clip loop tests `Task.isCancelled` and asks `ResourceGovernor.checkpoint()` before a new expensive unit; `ResourceGovernor` returning stop persists progress and returns control to UI.

## D. Unified review and protection integration

Every feature emits either `ReviewOpportunity` (a candidate needing a human choice), `VerifiedExactGroup` (full resource signatures), `NonDestructiveAction` (Favorite/Album/Protect/Save derivative) or `InformationalFinding`. Only the first two may reach the existing approval/tray flow; both must recheck N05 and native protection. A screenshot's OCR match, a quality score, a re-encoded video relation or model preference score must **never** be retyped as `completeResourceEquality`. Novel candidate IDs must be stable across launches via source revisions + evidence version; mapping to a tray group must preserve real current PhotoKit IDs.

Example draft:

```swift
enum NewFeatureOutcome: Sendable {
 case reviewOpportunity(category: String, assetIDs: [String], evidenceID: String)
 case exactVerified(assetIDs: [String], canonicalSignature: String)
 case information(messageKey: String)
 case noResult(reasonKey: String)
}
```

Data about current media identity should not enter diagnostics. Review opportunities cannot be counted as verified deletable bytes unless a user reviewed target with measured resources and an admissible keeper is established.

## E. Shared local reset, privacy and offline

Centralize clearing of local derived caches, training examples, optional local history, compression temporary files, rule stores (with explicit user confirmation) and diagnostic logs. Reset **never** performs a Photos mutation, and does not undo Favorites/Albums/photos already created by user actions. External iCloud originals require explicit download consent through existing `NetworkPolicy`, not an Nxx-specific silent network toggle. No analytics endpoint or remote feature flag; all user-visible counts can be recomputed locally. Reconcile sync/permissions on foreground entry.

## F. Stale revision and failure taxonomy

Standard error categories for view models: `needsAuthorization`, `scopeLimited`, `assetMissing`, `assetChanged`, `localOriginalUnavailable`, `unsupportedMedia`, `analysisTimedOut`, `memoryPaused`, `thermalPaused`, `evidenceInsufficient`, `writeCancelled`, `writeUncertain`, `storeMigrationFailed`. These are UI categories, not raw error descriptions. Every error leaves source Photos assets untouched unless a previously explicitly authorized PhotoKit change may have succeeded and must be reconciled. Avoid catching everything as 'No photos found'.

## G. Implementation tests across modules

- Feature views only consume app-level view models; no direct PhotoKit deletion function present.
- Pure Core algorithms can be unit tested on Linux; PhotoKit/AVFoundation/iPad layouts require iOS/macOS testing.
- `LibraryStore` can migrate forward from any supported old version and recover from interrupted backfills.
- Device phase never silently increases network access or video decoder worker count.
- A cached protection version mismatch invalidates prepared removal at final commit.
- The same feature's phone and iPad screens render distinct responsive layouts but produce identical domain commands for identical user choices.
