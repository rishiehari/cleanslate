# N08 — Album Inbox: nondestructive photo sorting and organization

**Priority:** after core review/scan stability. **Effort:** L, ~16–27 engineer-days depending on actual PhotoKit album API coverage and iPad drag UI. **Paid-market analogue:** Slidebox and similar organizer apps charge to make ordinary album sorting smoother; this feature is about speed, not new cloud AI. **Crucial distinction:** full-library Photos authorization supports a broader album workflow; Apple's *limited Photos* mode restricts album fetching/creation, so album features must degrade explicitly, not pretend they work.

## 1. Product outcome and first-value journey

A user may have no duplicates but still needs to organize recent photos into albums. CleanSlate should become useful even when it recommends deleting nothing. Album Inbox presents authorized, unfiled (as far as it can determine) photos alongside destinations such as user albums, explicit Favorites, Skip and Keep in Inbox actions. First value appears with a three-picture synthetic demo: user taps "Vacation" to file a travel photo, marks a pet photo Favorite and skips a receipt. Demo changes only local fake state, with a visible "Example photos" label; no Photos permission or mutation occurs. After authorization, show the newest accessible unfiled items and existing albums, allowing a first real album action within three taps when the user has granted full access.

**Important promise:** file into an album does **not** remove a photo from All Photos, and an album is not a backup. The inbox is a view of *current* authorized library state, not proof of every photo's album membership if permission is limited. A user can assign one photo to multiple albums, and selecting Favorite is separate from album membership. No deletion in this feature; the existing tray remains independent.

**Non-goals:** cloud sync of CleanSlate labels, alternate photo library, album encryption/vault, moving assets out of Photos, replacing Apple Photos' People/Pets classification, automatic bulk album creation without user review, organizing Hidden assets without authorization, or claiming Apple Photos albums can be fully manipulated in limited mode.

## 2. PhotoKit capability matrix

| Permission | Accessible assets | Fetch user albums | Create/edit user albums | Fallback |
|---|---|---|---|---|
| Full read/write | Current authorized library | Use documented `PHAssetCollection` APIs | Use `PHPhotoLibrary.performChanges` after explicit user choice | Full Inbox |
| Limited read/write | Selected asset subset | Apple's documentation restricts fetching user albums | Album actions unavailable in this mode | **Local labels** only, explicitly not synced to Photos |
| Add-only (where requested) | No unrestricted reading | No browsing | Not a full organizer capability | Offer to request appropriate access |
| Denied/restricted | None | None | None | Permission-free interactive demo and Settings guidance |

**Local labels are optional, not fake Photos albums.** In limited mode show "Collections in CleanSlate (on this device only)" and display/assign user-created local labels; never claim they appear in Apple Photos or synchronize across iCloud devices. If the user later grants full access, offer an explicit migration preview of local labels to real albums; no silent migration. Verify PhotoKit album write success by refetching collection membership. Deleting a CleanSlate local label never deletes Photos assets.

## 3. Source-of-truth and domain model

```swift
struct AlbumDestination: Sendable, Hashable {
 let id: String
 let displayTitle: String
 let kind: DestinationKind // applePhotosAlbum, localLabel, favorites
 let writable: Bool
 let reasonUnavailable: String?
}
struct OrganizationCommand: Sendable {
 let idempotencyID: UUID
 let assetIDs: [String]
 let expectedRevisions: [String:String]
 let destination: AlbumDestination
 let action: OrganizationAction // addToAlbum, favorite, localLabel
}
enum OrganizationResult: Sendable {
 case confirmed(verifiedAssetIDs: Set<String>)
 case partial(succeeded: Set<String>, unresolved: Set<String>)
 case cancelled
 case permissionChanged
}
protocol AlbumOrganizing: Sendable {
 func destinations(authorization: PhotoAuthorizationScope) async throws -> [AlbumDestination]
 func classifyInbox(after cursor: String?, limit: Int) async throws -> InboxPage
 func apply(_ command: OrganizationCommand) async throws -> OrganizationResult
}
```

Recheck live authorization and asset existence before any Photos write. Membership is many-to-many: an asset in one album may still be in the Inbox if the user's filter is "not in target album", but should be absent if scope is "in no visible user album" and full metadata confirms it. Clearly label that query definition. Album changes are not deletion and do not require the delete tray, but they do require a **single app-level serialized PhotoKit mutation owner** so concurrent album writes, Favorites changes and deletions don't conflict invisibly. Avoid taking over `PhotoDeletionCoordinator` for album changes; build a separate typed album/favorite coordinator while sharing mutation serialization and change reconciliation, never a second delete path.

## 4. SQL and operation journal

```sql
CREATE TABLE album_inbox_state(
 asset_id TEXT NOT NULL, revision TEXT NOT NULL,
 status TEXT NOT NULL CHECK(status IN ('unreviewed','filed','favorited','skipped','unavailable')),
 last_destination_id TEXT, updated_at REAL NOT NULL,
 PRIMARY KEY(asset_id,revision)
);
CREATE TABLE local_collections(
 label_id TEXT PRIMARY KEY, display_name TEXT NOT NULL,
 created_at REAL NOT NULL, updated_at REAL NOT NULL
);
CREATE TABLE local_collection_members(
 label_id TEXT NOT NULL REFERENCES local_collections(label_id) ON DELETE CASCADE,
 asset_id TEXT NOT NULL, revision TEXT NOT NULL,
 PRIMARY KEY(label_id,asset_id)
);
CREATE TABLE album_operation_log(
 operation_id TEXT PRIMARY KEY, status TEXT NOT NULL,
 destination_type TEXT NOT NULL, destination_id TEXT,
 source_revisions_json TEXT NOT NULL,
 created_at REAL NOT NULL, last_attempt_at REAL
);
```

Local label names are user content; keep them under filesystem data protection and exclude from diagnostics/export unless user explicitly requests. Operation log records only IDs and state needed for idempotency; long-term logs should be minimized after reconciliation. If Photos mutation might have committed before app crash, refetch album membership before retrying. A duplicate Add to Album should be idempotent if PhotoKit permits, but do not assume all changes are idempotent; test it. Favorites are a property change and may alter existing preservation flags, invalidating any pending delete tray references automatically.

**State machine:** `inbox → selected → destinationChosen → pendingPhotosWrite → verifying → filed/favorited/partial/error` with `skipped`, `localLabeled`, `permissionLost` and `interrupted` transitions. An operation may be `uncertain`; never show "Added to Photos album" until refetch verifies it. Auto-advance on successful file action only if the active item still exists and current window owns that review intent. Undo for a **local label** is immediate; undo for a Photos album action requires a new explicit Photos mutation and fresh state, not a fake in-memory reversal. Do not offer destructive undo of a Favorite made by user in Photos without explaining it affects the real library.

## 5. iPhone interface

**Home/entry:** "Organize photos without deleting" card. If full access, shows "Recent unfiled" count within scope. Limited: "Organize within CleanSlate only" with truthful disclaimer and manage access. Denied: demo.

**Inbox feed:** one large photo and horizontal album chips below, with Tap album, Favorite, Skip and Next. Users can open album picker, create a real album from a clear sheet, review destination name and apply. Do not automatically create destination albums based on AI labels. The screen always shows "This photo stays in All Photos" after filing; no deletion icon in the primary flow.

**Batch mode:** grid with explicit selection count; choose destination; final confirmation "Add 12 photos to Vacation". On success show actual verified number. On partial success: "9 added, 3 need a retry", with exact affected rows and no duplicate silent replay.

**End of session:** "10 organized · 3 favorites · 5 skipped" with buttons View album / Done. If no user albums exist, offer Create your first album or local label if limited; don't block browsing.

## 6. iPad native workspace

Wide: sidebar of album destinations, middle inbox grid with selection checkboxes, right large selected photo and album membership details. This is a real triple-pane organizing flow, not a stretched phone deck. Offer touch drag of selected cards to an album row **only** for a staged command; show a confirmation sheet with count and destination before PhotoKit write. Pointer hover highlights drop destinations; VoiceOver and keyboard have equivalent "Add to selected album" action. Keyboard arrows navigate grid, Space toggles selection, Command-F searches albums, Escape clears staged drag; Delete key never deletes assets. Album counts update after verified change, not optimistic unverified animation. On narrow Stage Manager window use bottom destination sheet and keep selected items. Multiple iPad windows are not yet supported; one active organizer shares the same app-level PhotoKit mutation gate and selection snapshots.

## 7. Edge and privacy cases

- Full→limited permission mid-operation: cancel/mark unresolved and avoid undisclosed album access.
- Album deleted/renamed while selected: refetch and validate its stable identifier; rename changes label, not ID.
- Asset edited or removed: request fresh revisions and skip unavailable items; no synthetic resurrecting.
- Album already contains item: show Already there, no duplicate success count.
- Asset in multiple albums: no implied move; add only to chosen destination.
- Hidden/shared/album-protected asset: honor Photos access and display; favorite/album changes may be allowed but deletion safeguards remain.
- Local label reset: explicit confirmation, never touches Photos albums.
- Offline: Photos album writes are local via PhotoKit; iCloud sync may happen later under Apple; don't promise immediate cross-device propagation.
- iPad drag source with 1000 selections: bounded batch/confirmation, no large retained thumbnails.

## 8. Acceptance tests

```gherkin
Scenario: Full-access album filing is verified
 Given a real Photos album named Vacation and an accessible photo not in it
 When I choose Vacation and confirm Add
 Then CleanSlate requests a Photos album mutation
 And shows Filed only after refetch confirms membership
 And the photo remains in All Photos

Scenario: Limited permission does not impersonate Apple albums
 Given authorization is limited
 When I open Album Inbox
 Then no unsupported user album enumeration is attempted
 And local labels are explicitly shown as on-device-only

Scenario: Favorite invalidates pending removal eligibility
 Given an asset is approved for removal elsewhere
 When Album Inbox successfully marks it Favorite
 Then the pending deletion is invalidated for review
 And the original cannot be committed under the stale approval

Scenario: Interrupted album write is reconciled
 Given Photos album add succeeded but the app quit before recording success
 When the app resumes
 Then it refetches membership before any retry
 And no item is counted twice
```

**Tests:** fake album catalog full/limited/denied, idempotent create/add, dropped asset, album renamed, Photos write cancel and partial, Favorite conflict with tray, 250k metadata query, on-device album and Favorites integration, iPhone AX5 and iPad keyboard/drag/resize, local label data reset. No personal real photos in CI. Proposed latency gate: user can file one already indexed item with at most three gestures; measured with a consented usability test, not claimed upfront.

## 9. Execution and rollback

1. Pure destination and membership model/tests (`Core/Sources/CleanSlateCore/OrganizationState.swift`).
2. `LibraryStore` schema, local label CRUD and operation ledger (`App/Store/LibraryStore.swift`).
3. PhotoKit album client adapter with documented permissions and reconciliation (`App/Services/AlbumOrganizer.swift`).
4. iPhone Inbox / album selector / batch confirmation (`App/Views/AlbumInboxView.swift`).
5. iPad split-view drag, keyboard and accessibility (`App/Views/iPad/AlbumInboxWorkspace.swift`).
6. Device mutation canaries and SafetyPolicy favorite invalidation tests.

Flag `N08AlbumInboxEnabled` OFF until gated; rollback hides organizer while retaining user-created Photos albums and local label data until user deletes it. Never remove photos to undo a feature flag. **Done:** true album membership verification, accurate limited-access fallback, no Photos deletion path, no accidental album move semantics, iPhone/iPad physical-device and a11y tests passed.

**Sources:** https://apps.apple.com/us/app/slidebox-photo-cleaner-app/id984305203 ; https://developer.apple.com/documentation/PhotoKit/browsing-and-modifying-photo-albums ; https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app
