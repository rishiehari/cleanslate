# N09 — Rescue Gems: rediscover photographs worth keeping

**Feature purpose:** counterbalance deletion with positive discovery. **Effort:** M, ~10–18 engineer-days plus human curation tests. **Premium analogues:** Flic's Best 25 and Swipewipe's On This Day rediscovery. **Privacy:** local ranking, no push notifications in initial release, no uploading or photo identity recognition. **Safety:** the feature never proposes deletion by itself.

## 1. Value proposition and first attempt

People take thousands of photos and forget high-quality, meaningful moments that were never favorited. Rescue Gems offers a small, diverse set of "worth another look" images from authorized portions of their library—without asserting an algorithm knows what is emotionally valuable. The first experience uses bundled synthetic images spanning a trip, graduation and pets, with a prompt "Which would you like to revisit?". Tapping a demo Favorite affects only fake state; no Photos access is required. Once real permission is granted, the app proposes a user-chosen 3, 10 or 25-image batch from the current indexed subset, explaining why a mix of time periods was included. One tap can Favorite a photo in Apple Photos through a single safely reconciled PhotoKit property change.

Make **Keep** a valid result, not a failure. End state can say "You revisited 12 photos and favorited 3" even when zero bytes are removed. An empty/no-photo state must not say "You have no good photos"; say "Not enough locally available photos were in the checked scope to assemble a varied set. You can explore the sample or select a bigger scope."

**Non-goals:** identify named people/relationships, emotional state, semantic search across private photos, reconstruct deleted originals, cloud library, viral leaderboards, daily streak quotas, push notifications, or promise new suggestions daily.

## 2. Candidate selection and diversity algorithm

Candidate source is *authorized* photo snapshots from paginated `LibraryStore`, with accessible local thumbnails/quality signals. Protect user privacy by excluding Hidden/unavailable/restricted assets according to current PhotoKit and product rules; a user-protected photo can still be *rediscovered* if explicitly opted in, but may never be suggested for removal. Prefer content from a spread of capture months/years, geographic diversity only if user explicitly enables and coordinates remain transient (geolocation NOT required), composition/technical-quality diversity without face identity, and assets not previously favorited or shown too often.

Build a stable candidate pool with a reservoir sampler across time buckets, not a sequential first-5000 preference. For each candidate, compute a bounded feature summary: quality validity, broad visual featureprint distance to already selected items, capture time/month, source resolution, existing Favorite and recent-show history. Define an objective that balances **time coverage + visual diversity + technical quality**, with explicit caps so one vacation cannot occupy the whole batch. Existing favorite photos may be optionally included in an "Old favorites" mode but default mode prioritizes never-favorited images. If quality unavailable, do not exclude all photos; use time diversity and stable sampling. None of these measurements establishes subjective memory value.

Greedy bounded selection: (1) choose a candidate from each requested time bucket, (2) repeat adding the item with best marginal diversity/quality until `k` reached, (3) mark less-recently-shown first with deterministic tie-break. Complexity is O(N log K) reservoir plus O(M·K) selection on bounded pool M (e.g. ~500–1000), not an all-library distance matrix. Configurable weights and pool caps are provisional; calibrate on human ratings of "Would you like to see this?" and test coverage bias. The discovery algorithm **never** outputs suggested removal IDs.

```swift
struct GemCandidate: Sendable {
 let assetID: String
 let revision: String
 let captureMonth: Int?
 let qualityEvidence: [QualitySignal]
 let visualDescriptor: Data? // derived and local, no face identity
 let priorShownCount: Int
}
struct GemBatch: Identifiable, Sendable {
 let id: UUID
 let assetIDs: [String]
 let evidenceVersion: Int
 let coverage: CoverageDescriptor
}
protocol GemSelecting: Sendable {
 func makeBatch(scope: ScopeDescriptor, count: Int,
                afterHistoryCursor: String?) async throws -> GemBatch
}
protocol GemFavoriting: Sendable {
 func setFavorite(assetID: String, revision: String,
                  favorite: Bool) async throws -> FavoriteMutationResult
}
```

Use the existing PhotoKit client or a narrow mutation extension for Favorites; serialize property writes with any album mutation and delete coordinator. A favorite operation can change preservation flags, so pending deletion approvals must be invalidated, not ignored. Never show Favorite success before refetch confirms. The feature should also support a "Keep as is" button that changes only CleanSlate local shown-history state.

## 3. SQLite and privacy retention

```sql
CREATE TABLE gem_batches(
 batch_id TEXT PRIMARY KEY, scope_id TEXT NOT NULL,
 algorithm_version INTEGER NOT NULL, created_at REAL NOT NULL,
 state TEXT NOT NULL CHECK(state IN ('ready','in_progress','completed','stale'))
);
CREATE TABLE gem_batch_members(
 batch_id TEXT NOT NULL REFERENCES gem_batches(batch_id) ON DELETE CASCADE,
 asset_id TEXT NOT NULL, revision TEXT NOT NULL,
 display_rank INTEGER NOT NULL, reviewed INTEGER NOT NULL DEFAULT 0,
 action TEXT CHECK(action IN ('favorite','keep','skip')),
 PRIMARY KEY(batch_id,asset_id)
);
CREATE INDEX gem_by_asset ON gem_batch_members(asset_id);
CREATE TABLE gem_show_frequency(
 asset_id TEXT PRIMARY KEY, revision TEXT NOT NULL,
 shown_count INTEGER NOT NULL DEFAULT 0, last_shown_day INTEGER
);
```

Only opaque IDs, revisions, dates coarsened to days, and decisions. No images, unredacted EXIF, face embeddings or GPS persisted for gem history. Local counters can be cleared; this may cause earlier images to be resurfaced but never change Photos originals. A permission decrease hides invalid entries and marks batch partial. A batch is *not* a saved album and does not sync between devices; do not state otherwise.

**State machine:** `noBatch → sampling → ready → viewing → reviewed/markedFavorite/skipped → completed`; `permissionLost`, `assetChanged`, `thumbnailUnavailable`, `pausedForThermal`, `cancelled` must preserve safe intent and not mark a favorite operation successful prematurely. On resume, a batch rechecks each member revision before showing it; unavailable members can be replaced only with visible notice, not silently counted reviewed.

## 4. iPhone UX specification

**Home entry:** "Find forgotten favorites" with honest coverage badge "From 1,340 photos checked". A no-permission user gets "Try a sample" before consent. Opening real view offers 3/10/25 Gems and a one-sentence value statement. Avoid a daily streak or any forced notification opt-in.

**Gem carousel:** one large image, date shown if available, explanation chip "From a different month" or "Not favorited yet" only when supported. Buttons **Favorite in Photos**, **Keep as is**, **Skip**, **Compare nearby** (opens the existing moment review if available but does not propose deletion). Pinch zoom, tap to view EXIF if user requests; no AI identity label. Favorite action announces pending/confirmed states and allows the user to view the result in Photos. Avoid confetti or a deletion scoreboard.

**Session recap:** "12 revisited · 3 newly favorited · 9 memories kept as they were." Show next batch only if scope has enough distinct images; otherwise "That's all for this scope." An optional once-a-week locally generated recap appears only when user opens CleanSlate. No background notifications required. Day-two value is a fresh nonrepeated selection if newly indexed items exist, not manufactured urgency.

**Failure states:** limited permission "Showing gems from selected photos only"; no eligible local thumbnails "Preview isn't available here"; no date metadata "Showing a varied sample"; when all photos are already favorite "Revisit old favorites" offer, not pretend something is unfavorited.

## 5. iPad UX specification

Wide iPad: photo mosaic in the central pane with category/time sidebar and a focused detail viewer; selecting one gem expands it while the mosaic remains visible. Pointer hover reveals Favorite and View details controls; keyboard arrows navigate, Space opens preview, F favorites only when focus is inside the gem viewer, Escape closes. Touch swipe navigates images without staging deletion. In narrow Stage Manager windows collapse to a vertical image viewer with a compact selected-photo strip. VoiceOver announces "Photo 4 of 12, from May 2024, not yet favorited" only when these attributes are known; it never infers a person or emotional event. Multiple windows are not enabled by the current project.

## 6. Evaluation, coverage and fairness

Use an opt-in 5-point local test question after a batch: "Were these worth revisiting?" Store only aggregate response/count on device; no individual image feedback leaves the device. In a consented human study compare algorithm against random-from-time-buckets baseline, newest-only baseline and existing favorites-only baseline. Evaluate session satisfaction, percentage of images accepted as worth revisiting, time diversity, repeated-photo rate and energy cost. Human evaluators must be able to say "I don't want the app to judge my photos." No ranking claims without measured results. Use diverse photo types—children, pets, documents, travel, food, screenshots, people in low light—and ensure favorite/quality signals do not systematically suppress important low-light moments. Avoid sentimental language such as "AI found your best memory".

**Scale budget:** sample from the already indexed authorized library; don't force full-library feature computation before first batch. Request thumbnails lazily for visible gems, cache a bounded next 2, evict on memory pressure. Under thermal pressure, continue viewing cached photos but pause generating new batch. PhotoKit image requests should default to local-only. No remote model or downloads to provide this feature.

## 7. Gherkin and fixture-based tests

```gherkin
Scenario: No photo access still demonstrates value
 Given Photos permission is denied
 When I open Rescue Gems
 Then I can interact with bundled sample photos
 And no real Photos API write or event is triggered

Scenario: Favoriting is a real Photos mutation
 Given an accessible unfavorited photo
 When I tap Favorite and confirm
 Then the Photos favorite flag is changed through the authorized client
 And the app shows confirmed only after a fresh snapshot verifies it

Scenario: Favorite invalidates deletion approval
 Given a candidate appears in an existing deletion tray
 When I mark it Favorite from Rescue Gems
 Then the stale tray entry requires renewed safety review

Scenario: A batch does not fake library coverage
 Given only 100 of 20,000 photos have been indexed
 When the app proposes 10 gems
 Then the UI attributes the selection to the 100 checked photos
 And never says it picked the best ten from 20,000
```

Fixtures: synthetic images across twelve months, one month's massive burst, all photos low-light, no date, same photo in several revisions, Favorites all true, limited-authorization subset, thumbnail failures. Test time diversity with seeded random input; deterministic output given seed and index generation; no visual feature availability; album/favorite changes during batch; iPad resize and VoiceOver; long-running pagination memory; read-only device demo. Device evidence must show actual Favorite sync behavior without real personal-library destruction.

## 8. Suggested implementation, local metrics, rollback

Commits: `N09.1` selection state and diversity tests; `N09.2` batch/review SQLite migration; `N09.3` bounded sampler using existing cached features; `N09.4` PhotoKit Favorite mutation and tray invalidation; `N09.5` iPhone carousel/demo; `N09.6` iPad mosaic/navigation/accessibility; `N09.7` evaluate and gate. Paths: `Core/Sources/CleanSlateCore/GemSelection.swift`, `App/Services/RescueGemsEngine.swift`, `App/Services/FavoriteCoordinator.swift`, `App/Views/RescueGemsView.swift`, `App/Views/iPad/GemGalleryWorkspace.swift`, `iOSTests/RescueGemsTests.swift`, `UITests/GemDiscoveryUITests.swift`.

Local-only counters: `gemBatchesOpened`, `gemPhotosSeen`, `gemFavoritesConfirmed`, `gemSkipped`, `gemRepeated`, `worthRevisitingResponseBucket`. Never store screenshot/asset IDs in diagnostic events. Feature flag `N09RescueGemsEnabled` OFF until shipped; rollback hides recommendation UI but does not undo real Photos favorites. **Definition of Done:** no deletion function reachable from gem cards, Favorite reconciliation and tray invalidation tested, honest partial coverage, iPhone/iPad UI + device accessibility, deterministic diversity and lifecycle tests complete.

**Sources:** https://apps.apple.com/us/app/flic-ai-photo-video-cleaner/id918263212 ; https://apps.apple.com/us/app/swipewipe-photo-cleaner/id1583884012 ; https://developer.apple.com/documentation/photokit/requesting-changes-to-the-photo-library


## Additional edge cases

A Photos library consisting mostly of screenshots or documents must not lead to an embarrassing "best memories" claim; show a neutral curated sample and let the user filter media types. An empty creation date, a single-month library, a repaired Photos thumbnail, an asset edited while displayed, limited authorization re-selection, a Favorite changed on another device and nonrepeatable sampled ranking must each have an explicit fallback. If all remaining candidates are protected or already favorited, use an old-favorites mode or finish gracefully. If the user disables local history, repeat avoidance becomes best-effort and must not be advertised as durable.
