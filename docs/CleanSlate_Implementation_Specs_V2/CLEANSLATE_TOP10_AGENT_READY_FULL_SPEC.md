# CleanSlate — TOP 10 Premium-Parity Features: Full Agent-Ready Specification

2026-11-12 | Native SwiftUI / PhotoKit / Vision / AVFoundation / SQLite | 100% free on-device by design

**This is a proposed implementation specification; the new features are not implemented or device-validated.** Individual editable files are available in this same package.

# CleanSlate — Premium-parity implementation specifications V2

**Prepared:** 2026-11-12. **Scope:** ten individually implementable, fully free, on-device features for iPhone and iPad. **No production code has been changed.**

This package is intended to be copied into the `rishiehari/cleanslate` repository under `docs/next-features/` (preserving these relative paths). It is a substantially more operational artifact than a market-analysis summary. Each feature has a stable identifier, typed contracts, proposed SQL, exact state transitions, phone/tablet UI requirements, failure semantics, fixtures, test cases, phased commits, and a Definition of Done. Common contracts here apply in addition to feature-specific contracts.

## Start here

1. `shared/00_REPOSITORY_BASELINE.md` — what the existing app already has, what is blocked, and what not to rewrite.
2. `shared/01_ENGINEERING_INVARIANTS.md` — all features must satisfy this safety, privacy, scale, and evidence contract.
3. `shared/02_DATA_AND_MIGRATION_STRATEGY.md` — migration ownership, cache lifetimes, crash recovery, data protection.
4. `shared/03_IPHONE_EXPERIENCE.md` and `shared/04_IPAD_EXPERIENCE.md` — separate screen architecture and interaction contracts.
5. `shared/05_FIRST_SESSION_AND_ENGAGEMENT.md` — truthful first value and private counters.
6. `shared/06_TEST_AND_RELEASE_GATES.md` — device matrix, benchmark definitions, Gherkin and adversarial tests.
7. `shared/07_DEPENDENCIES_AND_ROADMAP.md` — one-feature-at-a-time implementation order.
8. `features/Nxx-*.md` — the ten complete implementation specifications.
9. `agents/MASTER_AGENT_HANDOFF.md` — copy-ready instructions for any coding agent.

## The ten features

| ID | Name | Primary value | Relative effort | Mandatory prerequisite |
|---|---|---|---|---|
| N05 | Never Suggest / Protection Rules | Trust controls that truly block unsafe suggestions | M | safety tests, storage migration contract |
| N04 | Storage Goal Planner | A credible route toward a user-defined target | M | scoped scan/coverage and N05 |
| N07 | Screenshot Intelligence | OCR-aware repeat clutter with changed-text protection | L | scoped scan, screenshot category and N05 |
| N06 | Mistake Finder | Explain possible blur/dark/low-resolution issues | M | quality-signal calibration, N05 |
| N01 | Moment Intelligence / Best-Shot+ | Multiple keepers and meaningfully better burst review | XL | stable grouping, held-out human evaluation |
| N02 | Similar and Re-encoded Video Finder | Surface large visually redundant videos | XL | AVFoundation test corpus, resource governor |
| N03 | Compression Lab | Loss-controlled, opt-in media reduction | XL | N02 and crash-safe replacement ledger |
| N08 | Album Inbox | Fast nondestructive organization | L | permission matrix and single PhotoKit mutation coordinator |
| N09 | Rescue Gems | Rediscover value in photos worth keeping | M | calibrated quality, inclusion/diversity tests |
| N10 | Local Taste Personalization | Private queue ranking from explicit preferences | XL | all earlier safety gates, offline model ablation |

These are **implementation order**, not the numerical ranking used in the earlier research summary. Existing `F01–F10`, `S01` and the iPad work remain their own roadmaps.

## Research and claim discipline

Competitor capabilities are *advertised claims*, not reverse-engineered truth. The evidence URLs and caveats are in `shared/08_COMPETITOR_EVIDENCE.md`. All numeric thresholds in this package are proposed engineering gates or launch experiments, **not measured results**. Algorithm sketches are implementation contracts, not proven model accuracy. Never use synthetic fixtures as evidence of real-world quality.

## Build and test discipline

```sh
git clone https://github.com/rishiehari/cleanslate.git
cd cleanslate
git rev-parse HEAD
make core-test
make fixtures-test
make eval
make lint
make gen
make build
make ios-test
make budget
```

Run the repo's actual `make` targets only after checking them against `Makefile`. `make budget` requires a suitable simulator and is not a substitute for real-device memory, energy, Vision or Photos tests. Stop when an existing gate fails and record it; do not silently waive a failing gate to implement the next feature.

## What this package does not claim

It does **not** include a built app, completed feature implementation, certified safe deletion of real photos, measured model precision, or real-device validation. It does **not** authorize deletion on private/iCloud Photos libraries or a public App Store release. Apple Photos merge behavior is not available as a general third-party PhotoKit operation. All deletion still goes through the existing review, tray, system permission and commit-time validation.



---

<!-- Source: shared/00_REPOSITORY_BASELINE.md -->

# Repository baseline and integration checklist

**Observed via the connected GitHub repository on 2026-11-12:** https://github.com/rishiehari/cleanslate, default branch `main`. The repo is actively edited by multiple agents: **do not rely on a fixed branch hash from these specs**. Record `git rev-parse HEAD` and `git status --short` at each feature start. This is a source snapshot, not a claim that the codebase is fully green.

## Current source contracts — checked against actual files

| Existing code | Verified shape | Integration instruction |
|---|---|---|
| `Core/Sources/CleanSlateCore/SafetyPolicy.swift` | `evaluate(_:configuration:)`, `hardBlocked(_:)`, `validateCommit(_:currentByID:)`; requires direct evidence to a keeper | Reuse, never create a second independent deletion-eligibility function |
| `App/Services/PhotoLibraryClient.swift` | `@MainActor PhotoLibraryClient`, inventory pages, snapshots, thumbnails, digests, album membership, `delete(ids:expectedRevisions:)`, change subscription | Add narrow extension protocols/adapters; do not make unrelated services reach into `PHPhotoLibrary` |
| `App/Services/PhotoDeletionCoordinator.swift` | `commit(group:selected:manuallyReviewed:keeperIDs:)`; re-fetches, rehashes exact originals, revalidates revisions and routes to PhotoKit | NO shortcut, reimplementation, or direct `deleteAssets` call |
| `App/Store/LibraryStore.swift` | One SQLite actor with WAL and `PRAGMA user_version`; `schemaVersion = 1` in inspected content; asset, feature, digests, group, receipt tables | Migration numbers **must be allocated from actual HEAD**, not blindly copied from this package |
| `App/Services/ScanEngine.swift` | Main-actor resumable scan, candidate caps, Vision error counting, caches, `ResourceGovernor` | New classifiers are independent bounded jobs; no new full-library blocking scan on launch |
| `App/Store/DeletionTray.swift` | `TrayEntry`, `StandaloneTrayEntry`, `DeletionReceipt`, authorizations and receipts | Existing tray is only destructive-work ingress |
| `App/Services/ResourceGovernor.swift` | Thermal/low-memory/Low Power Mode checkpoint, cache-dropping hooks | Each ML/video worker must call governor checkpoints, honor cancellation and keep local-only defaults |
| `App/Models/PhotoModels.swift` | `PhotoSnapshot`, `PhotoReviewGroup`, `GroupKind`, `ScanStatistics` | Avoid overloading `GroupKind` to represent unrelated new feature state |
| `project.yml` | iOS 26 app minimum, Swift 6, universal family `1,2`, multiple scenes disabled | Both phone and tablet targets share one app binary and one mutation owner |
| `Makefile` | `core-test`, `fixtures-test`, `eval`, `lint`, `ci`, `build`, `ios-test`, `budget` | Use actual target commands, record execution results |

## Roadmap coordination and known validation risks

- The README reported **115 Core tests** on 2026-11-11. Test count changes with commits; never use that number as proof of current HEAD quality.
- `docs/FEATURE_ROADMAP.md` owns F04 Recent-100, F05 progress, F06 first-run trust, F07 local activity/impact, F08 coverage, F09 kept-safe, F10 accessibility/release. New features must compose with them and avoid duplicates.
- `docs/features/S01-swipe-n-save.md` and `docs/plans/SWIPE_N_SAVE_PLAN.md` cover two-photo swipe flows. N01 must complement this experience and not erase its review/Approve/Tray separation.
- `docs/plans/IPAD_APP_PLAN.md` outlines native iPad. `docs/plans/IPAD_IMPLEMENTATION_LOG.md` reports a **partial universal target and adaptive review workspace**; full iPad simulator/device tests remained blocked in that log. Treat iPad as partially implemented, not absent or complete.
- Repository log says F03 real-device scan stability gate remains pending. Do not declare shipping readiness from simulator success alone. Current shared tree may also have in-flight scope work that requires integration; verify before any source edit.
- `docs/PROGRESS.md` is referenced by other docs but was not retrievable at the observed repository snapshot. Confirm whether it was moved/recreated. Do not invent its contents.

## Before coding each feature

1. Verify current HEAD, uncommitted changes and active feature branch. Read `AGENTS.md`, `docs/AGENT_ROLES.md`, `docs/FEATURE_ROADMAP.md`, `docs/IMPLEMENTATION_ORDER.md`, `docs/VALIDATION_LOG.md`, `docs/PRODUCT.md`, the appropriate old feature spec, and the new Nxx file.
2. Search for already implemented abstractions. Write an ADR for any new long-lived service. Record whether the feature needs new Photos read access, write access, or background task declarations.
3. Allocate SQLite migration **after the last migration present in current HEAD**. A migration proposal in this package is a change template, not a license to overwrite concurrent migrations.
4. Add a failing unit test for the central invariant, then implement pure logic before PhotoKit-specific I/O, then UI.
5. Integrate the existing app shell and iPad adaptive shell; do not create an isolated second root view or new app target.
6. Update current roadmap/progress and validation logs only after actual tests. All GitHub branch/push/release permissions must follow the repository owner's explicit instructions and CI protections.

## Non-goals for this documentation

No SDK-private APIs, Photos database access, iCloud quota scraping, undocumented resource byte properties, cloud ML, vendor server, ad SDK, analytics SDK, subscription runtime, hidden photo upload, automatic deletion of near duplicates, or unbounded simultaneous work.



---

<!-- Source: shared/01_ENGINEERING_INVARIANTS.md -->

# Cross-feature engineering invariants

Every Nxx feature MUST satisfy these constraints. Treat them as executable acceptance requirements, not aspirational design rules.

## I-01 — Single authority for photo deletion

The only permitted user-visible flow is **Review → explicit Approve → DeletionTray → explicit Delete → system Photos confirmation → fresh reconciliation**. New features may produce review candidates; they cannot call `PHAssetChangeRequest.deleteAssets` or `PhotoLibraryClient.delete` themselves. `PhotoDeletionCoordinator.commit` remains the coordinator. Existing `SafetyPolicy.validateCommit` is applied to fresh live `AssetRecord`s, with direct evidence for each target-to-surviving-keeper relationship. A target protected by a hard safety flag never becomes deletable through a setting, personalization or storage-goal optimization. In particular, `A≈B` and `B≈C` never establish `A≈C`.

**Mandatory test:** verify that every new model's `suggestedRemovalIDs` is either empty, or only contains records whose preselection remains allowed by the shared safety policy; similar, low-quality, video and screenshot classifiers default to **manual** decisions. For a non-grouped standalone selection, use existing standalone review safety and never fabricate a keeper.

## I-02 — Revision and permissions are time-varying

All cached recommendations carry `assetID`, library revision and `algorithmVersion`. A PhotoKit change, limited-library selection change, edited asset, favorite change, album membership change, new shared-owner context or disappeared asset makes the relevant draft **stale**. Stale approvals must be re-rendered, not silently auto-repaired into a new deletion choice. Check authorization at request start, after background resume, before destructive commit and after returning from Settings.

Limited access means only user-authorized assets are visible. Do not claim coverage of the whole camera roll or enumerate/fetch user albums in this mode. Offer the system's limited-library selection management only in context.

## I-03 — Privacy, storage and offline boundaries

All inference runs on device by default. No account, upload, analytics SDK, remote config, cloud service, network telemetry or paid third-party API. Photo pixels and OCR text should be transient; no images, face embeddings, raw OCR, paths, GPS or personal identifiers in logs. Derived sensitive fingerprints should be keyed, versioned, encrypted by system data protection and easily deleted with CleanSlate local data. Keychain access material must not be exported in diagnostics.

PhotoKit originals may be unavailable locally. The default remains `allowNetwork: false`; any opt-in iCloud original download must reuse the existing `NetworkPolicy` and show expected size, cellular conditions, cancellation and budget. No feature silently turns network access on.

## I-04 — Separate four storage quantities

Maintain typed quantities (no stringly typed `Double GB` in domain models):

```swift
struct StorageEvidence: Sendable, Codable {
    let eligiblePotentialLogicalBytes: Int64?  // validated candidate resource sizes, not freed space
    let verifiedRemovedLogicalBytes: Int64?    // receipt after live Photos reconciliation
    let localFreeSpaceDeltaBytes: Int64?       // noisy OS before/after observation
    let iCloudQuotaRecoveredBytes: Int64?     // must remain nil: not reliably attributable
    let coverage: CoverageDescriptor          // indexed/verified/unknown/limited scopes
    let measuredAt: Date
}
```

Potential bytes are never called 'already freed'. Verified removal does not guarantee an immediately matching local-capacity delta: Recently Deleted, shared media, iCloud optimization and Photos storage accounting can differ. Avoid adding hypothetical compression deltas to confirmed deletions. Show coverage and unknowns prominently.

## I-05 — Resource limits and continuous feedback

No broad scan in a SwiftUI view body, PhotoKit change callback, or app launch. Work is cancellable, checkpointed and bounded; heavy media decoding uses a single active worker at the lowest device tier until real measurement permits more. Existing `ResourceGovernor` supplies thermal/memory/Low Power Mode policies; stop/retry/resume must be visible. Never retain decoded video frames across an entire batch. Every data-bound UI has loading, empty, blocked, partial, stale, cancelled and error states.

**Proposed budgets pending device measurements:** no main-thread stall over 250 ms in synthetic 10k-library tests; cancellation becomes observable within 2 s at safe checkpoints; never exceed the repo's tier-specific measured memory ceiling; no unbounded O(N²) comparisons. Do not present simulator footprint as phone physical memory evidence.

## I-06 — Single source of truth across iPad and iPhone

One app-level `PhotoLibraryClient`, `LibraryStore`, `DeletionTray`, `ResourceGovernor`, and delete coordinator. Presentation state is scene-local; mutation state is app-global. Resizing/reorientation must not create another scan or rerun approval. The iPad has its own composition, keyboard, pointer and multi-pane UX rather than a scaled phone; the same eligibility, permissions, storage and safety rules apply. Multiple independent windows remain unsupported until separately tested (current project disables multiple scenes).

## I-07 — Calibrated uncertainty

Confidence scores are not probabilities unless calibrated on representative held-out device-appropriate data. Label scores 'quality indicators' or 'possible match' until validated. No eye-open, emotion, person identity or content importance claim from an unsupported generic model. Feature gates stay OFF if accuracy evidence or physical-device hardware support is incomplete. Unknown evidence must produce review-only, skip or no-recommendation—not an optimistic deletion.

## I-08 — Release and recovery

Every stateful feature needs a crash/kill/resume test, schema upgrade test, schema rollback story, permission-revocation test, and destructive-operation audit. Any Apple Photos mutation must survive: system prompt cancellation, operation timeout, partial success/uncertain reconciliation, app process death and library change concurrent with action. Release flags are compiled defaults, not remotely controlled. Do not use 'Tests passed' for tests not executed on the exact branch.



---

<!-- Source: shared/02_DATA_AND_MIGRATION_STRATEGY.md -->

# Data ownership, migration allocation, caching, and crash consistency

## 1. The repository's actual database

The observed `App/Store/LibraryStore.swift` owns one SQLite connection behind an actor. Its source declares `schemaVersion = 1` and a `migrations: [String]` list. In the same inspected source, v1 creates `meta`, `assets`, `features`, `digests`, `groups`, `group_members`, `reviews`, and `receipts`. There may be newer migrations by the time a feature starts. **Never copy a feature's `v2`/`v3` label blindly.** The feature SQL snippets below are templates to append to the latest migration, with dependencies implemented before their use. Assign and document exact `PRAGMA user_version` in the implementation PR.

The database is a **rebuildable index**, not the authoritative Photos library. `LibraryStore.reset()` must not silently destroy user decisions or receipts; give nonrebuildable preferences and approved tray state explicit ownership and reset semantics.

## 2. Proposed shared relational model

```sql
-- Namespace for independent feature migration batches, not a literal single next-version migration.
CREATE TABLE IF NOT EXISTS feature_progress (
    feature_id TEXT PRIMARY KEY,
    schema_version INTEGER NOT NULL,
    algorithm_version INTEGER NOT NULL,
    cursor_json TEXT,
    status TEXT NOT NULL CHECK(status IN ('not_started','running','paused','completed','stale','failed')),
    scanned_count INTEGER NOT NULL DEFAULT 0,
    unresolved_count INTEGER NOT NULL DEFAULT 0,
    updated_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS local_impact_event (
    event_id TEXT PRIMARY KEY,
    feature_id TEXT NOT NULL,
    event_kind TEXT NOT NULL,
    created_at_bucket INTEGER NOT NULL,
    duration_ms_bucket INTEGER,
    count_bucket INTEGER,
    bytes_bucket INTEGER,
    schema_version INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS impact_by_feature ON local_impact_event(feature_id, created_at_bucket);
```

An event may contain **numeric bins**, never raw asset IDs, OCR tokens, filenames, location, person identity, face embeddings, exact photo timestamps or media. Keep only a bounded 90-day local rolling window unless user chooses 'Retain history on this device'; this is a proposed product policy, not a preexisting repo guarantee. All counters recompute from local records where feasible to prevent drift.

## 3. Asset-scoped cache key

For any new feature cache, use the composite identity `(asset_id, asset_revision, algorithm_version, model_version, relevant_parameters_hash)`. On every read verify the current asset revision, known authorization scope, safety protection version and model hash. Do not reuse `dhash` as a unique identifier. An asset can have a Live component, RAW+JPEG, adjusted edit, or multiple resources; use `PHAssetResource` type when reading only accessible metadata. Cache *only* derived values required for current features. Eviction must be deterministic and tested.

## 4. Migration pattern

Append an ordered migration to the existing actor migration list. Use `BEGIN IMMEDIATE`/`COMMIT` with rollback on error; do not alter migration history. After adding each table, create matching indices and a transaction integrity test. If backfill is needed, put it in a resumable job rather than a long migration blocking launch; store backfill progress and per-asset version. A migration that needs to transform user-protection rules must fail closed and leave protection enabled on unexpected input.

Suggested test sequence:

1. Create a temporary DB at the preceding real user_version.
2. Populate assets, features, digests, groups, reviews, receipts and tray-serialized data representing protected/edit/Live/media cases.
3. Open with the new `LibraryStore`, assert version increment and all existing values preserved.
4. Simulate a process crash between backfill pages, reopen and continue without duplication.
5. Simulate malformed feature payload, expect no crash and stale feature disabled.
6. Simulate downgrade to older app binary: older binary must not overwrite/interpret unknown columns. Document policy (block old binary or store only additive data).
7. Run `PRAGMA integrity_check` after migration; check that index and child-table counts match.

## 5. Crash-safe work ledger

Each long-running job gets an immutable `job_id` (UUID) with phase/status. Write per-step checkpoints before expensive I/O. A resumed job revalidates PhotoKit permissions and live revisions and never assumes an old result is still safe. Staging temporary exports must be in application-controlled protected storage with `NSFileProtectionCompleteUntilFirstUserAuthentication`, excluded from backup; cleanup abandoned files after checking against the job ledger. A media derivative `createdAssetID` becomes known only after Photos reconciliation; never treat an attempted Photos creation call as proof.

Atomic data decisions that must be in one SQL transaction: user protection rule + its version update; swipe approval + prepared draft state; compression job stage and output asset identifier; album operation state + idempotency key; model opt-in + version and reset state. PhotoKit changes cannot be transacted with SQLite. Therefore use a **saga**: `pending → Photos operation → verify PhotoKit state → database reconciliation`, recording uncertain operations explicitly.

## 6. Privacy controls and per-feature reset

The Settings screen must expose a **Delete CleanSlate Local Data** action. Its confirmation discloses: generated fingerprints, OCR-derived fingerprints, on-device activity counters, model preferences, temporary compression outputs, category selections, scan cursors, protected lists, and optional diagnostics. The currently approved deletion tray is user safety state: clearing it requires a dedicated explicit description and must not cause deletion. Do not clear Apple Photos library assets through this function. Revoking Photos access does not itself delete private local data; offer a separate reset.

## 7. Query discipline at scale

For 250k indexed assets: use `LIMIT` + deterministic keyset cursor `(created_s,id)` or rowid with an explicit stable snapshot; avoid a `SELECT *` materialized Swift array. For candidate retrieval use approximate/bucketed heuristics and bounded collections, never an all-pairs video/screenshot/Moment comparison. Proposed query budgets should be recorded in instruments (p50/p95 and peak RSS), not invented. The initial implementation must not promise exhaustive search when query caps/truncation apply; show a coverage ledger including exact counts examined, feature families skipped, permissions limitations and iCloud unavailable items.



---

<!-- Source: shared/10_CROSS_FEATURE_ARCHITECTURE.md -->

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



---

<!-- Source: shared/03_IPHONE_EXPERIENCE.md -->

# iPhone-specific experience contract (not an enlarged iPad)

**Scope:** portrait-first, one-hand review, shallow navigation, compact screens and explicit destructive safety. Every feature file supplements this base with unique views and transitions. The app minimum currently declared in `project.yml` is iOS 26. Respect actual safe areas and Dynamic Type instead of freezing screen-pixel assumptions.

## Main navigation

Use existing dashboard and category routing; don't add ten permanent tabs. Recommended destination groups: Home, Swipe & Save, Discover, Review Tray, Settings. New features appear contextually as Home recommendations and Discover categories. The `AppDestination` navigation model (if/when added) must have stable identifiers to survive foregrounding and tab switching. Do not move an approved photo back into an unapproved selection merely because the user navigates backward.

## Standard first-value card

Every new feature that is empty until scanning completes must display one of three honest states: a seeded interactive *demo* (explicitly labeled "Example photos"), an already indexed real result (with scope and date), or a quick start action to analyze a bounded user-selected scope. It must never ask full-library permission just for browsing a static demo. A demo decision never calls PhotoKit mutation and never appears in real history/impact. Put the first actionable decision within two taps after an eligible result exists; instrument the actual value only on device.

## Review surface requirements

Portrait: use one card/photo or pair at a time, horizontally safe gestures away from the system back edge, large bottom controls in the thumb region, and pinned top metadata limited to 2 lines. Narrow phones: buttons wrap/stack without clipping; `minimumScaleFactor` is not a substitute for readable Dynamic Type. Large-text accessibility uses an explicit vertical review layout with controls following content rather than overlaying photos. Landscape: prefer useful full-image visibility with a right-hand action rail, keeping navigation and tray count accessible. Never hide safety reasons behind tooltip-only UI.

Standard actions: **Keep**, **Keep both**, **Review**, **Skip**, **Protect**, **Add to tray** (only after explicit approval), **Undo** (undo staged action, not Apple's completed delete). Labels should say "Ready in your tray" rather than "Freed space" after approval. Every potentially destructive action displays the surviving/photo context. Use `.confirmationDialog` or equivalent system confirmation for uncertain selections, but do not replace Apple's Photos deletion prompt.

## Gestures and haptics

Gestures are optional accelerators with equivalent named buttons. Swipe n Save's agreed semantics must be preserved: left retains left; right retains right; up keeps both. Don't capture scroll gestures inside multi-photo grids. A swipe decision does not itself approve removal. On iOS with VoiceOver enabled, expose custom actions without requiring directional dragging. Haptics are subtle, respect Reduce Motion, and never convey the only representation of success/failure.

## States and copy rules

- `noPermission`: "See a sample first. Photos access is optional until you scan." CTA: "Choose photos to check".
- `limited`: "Checking only the photos you've shared with CleanSlate." CTA: "Manage selected photos".
- `running`: "Checked 74 of 100 accessible items" plus current stage, reason for any pause, and **Pause**.
- `partial`: "Some originals were only in iCloud. Those files weren't verified." CTA: "Review available results".
- `empty`: "No eligible items found in this scope" plus next valuable action, not "Your library is clean".
- `stale`: "Some photos changed. Let's refresh these suggestions." CTA: "Recheck".
- `offline`: only mention network if user explicitly opted into original downloads; most features run offline.
- `error`: a clear retry path, no deletion or corrupted empty state.

## Accessibility, localization and usability

Visible controls ≥44×44pt; semantic headings; accessible image descriptions describe **why** items are shown, not subjective facial or emotional judgments. Announce changes to review state, with no repeated VoiceOver chatter for every scan counter tick. Support VoiceOver, Switch Control, Full Keyboard Access, bold text, Increase Contrast, Reduce Motion, RTL and English text expansion to at least 150%. All retention and protection actions must be discoverable without swiping.

## Screens shared across feature work

Home shows at most three relevant next actions. Discover lists categories; a FeatureView provides scan/coverage, result queue, detailed review, and an exit that preserves draft state. Tray remains the single destination for approved deletion; History stores confirmed operation receipts, not raw image content. Settings contains privacy, permissions, local data reset, download consent and relevant feature toggles. Do not duplicate tray/receipt logic in new views.



---

<!-- Source: shared/04_IPAD_EXPERIENCE.md -->

# iPad-specific implementation contract

**Current repo:** `project.yml` already targets iPhone and iPad (`1,2`) and disables multiple scenes; `docs/plans/IPAD_IMPLEMENTATION_LOG.md` reports partial adaptive review layout and a blocked iPad simulator test. This document describes the full tablet feature-level contract and does **not** claim that these layouts are already released.

## Adaptive composition

The iPad must use actual available window width and Dynamic Type environment, not `UIDevice.userInterfaceIdiom` alone. Proposed container: `NavigationSplitView` (sidebar + category queue + detail), collapsing to a phone-like `NavigationStack` for narrow Stage Manager windows. Do not nest multiple permanent split views. The UI may show three panes only when each photo can meet the minimum useful comparison width; otherwise collapse the queue. Preserve selected feature, queue item, zoom, compare mode, and unapproved draft through resize/rotate.

Suggested layout *behavioral bands* (calibrate with screenshots, not hardcoded policy):

- **Compact window:** one-column, photo-first, bottom/toolbar actions; full parity with iPhone.
- **Medium:** collapsible categories sidebar, main review with contextual queue sheet/popover.
- **Wide:** persistent category sidebar, review queue, double-image synchronized comparison; right-side details drawer optional.
- **Large text/AX5:** collapse the queue even on a wide iPad if two image panes would become too narrow; avoid clipping labels.

Multiwindow is **not** available in current project. Do not promise it. If a later phase enables multiple windows, introduce a single app-global actor for scan, tray and PhotoKit mutation; scene-local navigation alone may be duplicated. Two windows must not independently approve opposing keeper choices or submit a delete transaction.

## Tablet interaction essentials

- Touch: native gestures restricted to review canvas, not drag within sidebar.
- Keyboard: focused review can map Left / Right to keeper selection, Up to Keep both, Space to pause/resume, Escape to dismiss choice, Command-Z to undo a staged action. These are *suggested bindings*; final shortcuts need conflict/accessibility review. `Delete`/Backspace must never immediately delete a Photos asset.
- Pointer: hover is visual affordance only, never changes selection or approval; right-click can open Compare, Protect, Skip, not Delete.
- Drag and drop: Album Inbox may allow Photos IDs only as local opaque transfer objects; drop targets are visually and semantically labeled. No drag-to-trash shortcut around the tray.
- Zoom: synchronized side-by-side pan/zoom for comparison with an explicit unlink control; large images fetched only on deliberate zoom, bounded/cancelled.
- Apple Pencil: behaves as a pointer/touch; drawing/stylus-specific annotation features are non-goals.

## Tablet navigation by feature family

- **Storage Goal:** category queue on left, goal summary and evidence in center, selected group comparison on right.
- **Moment/Video:** filmstrip and group list on left, side-by-side image/filmstrip in detail, keeper set and protections persistent.
- **Screenshots:** categories/filters sidebar, OCR-safe group grid, enlarged comparison with changed-text highlighting only while actively displayed.
- **Compression:** job list + Before/After preview + inspector of verified quality/bytes; split view must never imply Photos original already deleted.
- **Album Inbox:** albums sidebar, current inbox grid, selected photo detail; keyboard, pointer and VoiceOver equivalents to drag-and-drop.
- **Rescue Gems:** photo mosaic in detail, date/album sidebar, favorite actions; no intrusive animation.
- **Local Taste:** preference examples with a sidebar for controls and reset, not an opaque "AI settings" screen.
- **Protection Rules:** filterable rules list and live coverage inspector; a rule editing panel must not turn into a global destructive shortcut.

## Persistence, focus and identity

Display scene state (selection, search, zoom) is separate from domain state (scan, protected rules, approved deletion tray). On navigation back or resize, don't create new long-running tasks. Revalidate restored `asset_id+revision` before showing a destructive draft. Keyboard shortcuts only operate in a focus-scoped review scene, never while editing a text field, dismissing a sheet or using VoiceOver navigation. UI tests must cover rotation while review, window resize during scan, category switching with unapproved drafts, and tray consistency.

## Test grid

Use at least one iPad mini-sized window and one large iPad Pro-sized window, in portrait and landscape, and test a narrow resized window plus AX5. Assert no overlapping action controls, no invisible approval/abort affordances, preserved keeper state, no extra library client instances, and bounded decoded image memory. A passing iPhone simulator or isolated iPad compile does not satisfy this device gate. Real iPad confirmation/deletion and VoiceOver need their own device evidence.



---

<!-- Source: shared/05_FIRST_SESSION_AND_ENGAGEMENT.md -->

# First-session UX, onboarding and local engagement specification

## A. Product objective

**Outcome:** a new user understands what CleanSlate will *and will not* do, sees genuine value on the first attempt, and can exit without deleting anything. The experience is free without payment gates, advertisements, trials, accounts or tracking. Some personal libraries contain no exact duplicates; meaningful first-use outcomes may be a correct Keep both, a protected family picture, a useful screenshot difference, one photo favorite or one organized album.

## B. End-to-end journey with conditional branches

### T=0–30 seconds: permission-free practical demonstration

On launch, a one-screen promise: **"Find the copies. Keep the moments. You decide."** Two concise guarantees immediately visible: "Photo analysis stays on this device" and "CleanSlate can't delete without your approval and Apple's confirmation". Buttons: **Try with example photos** (primary) and **Check my photos** (secondary). Existing onboarding may already display three pages; integrate instead of adding another mandatory flow. `Try` loads 4–6 bundled dummy scenes with choices: protect birthday shot, keep two different expressions, compare ticket screenshot with changed boarding gate. The demo must be interactive within 15–20 seconds of app launch on a supported phone, with actual timing measured. This is *fake data explicitly labeled*, not a misleading claimed real scan. Record no simulated progress into real impact.

### T=30 seconds–3 minutes: intent and scoped real value

Ask user intent in one compact view: **Find storage**, **Review similar moments**, **Organize & rediscover**. Map to N04/N01/N08 or existing categories depending on feature flags. Request Photos authorization *in context*, offer limited Photos access as a respected choice, and use existing F04 Recent-100 scope **only if it has actually shipped and passed its device gates**. If not, explain current scan scope and give a deliberate Start Scan action; never mislabel a full scan as Recent-100. Show actual progress with stage, examined count, unavailable cloud-only count, pause and cancel; don't invent seconds remaining. As results appear, show the highest **safely explainable** item first, not highest deletion pressure.

Decision card: a pair with clearly different expressions may lead to **Keep both**. App responds "Both kept. Nothing added to the tray." A true exact pair can lead to Add to tray after explicit photo review; app responds "One photo ready in your tray. It's still in Photos." A single protected item responds "Protected from CleanSlate suggestions on this device." Album filing responds "Added to Vacation" only after PhotoKit verification. The user should see one true outcome even if no bytes are recoverable.

### T=3–10 minutes: controlled review without fatigue

Home shows **at most three** next actions: highest evidence quality, best known potential logical bytes, and one positive action (Gems or Album). User may open Swipe n Save for two-photo decisions, N07 screenshot repeated packs, or N05 protection. Every review screen has Skip, Keep/Keep both, and a clearly labeled Done for now. Session progress counts reviewed groups/items and current **tray-approved** items separately from **verified deleted** results. No "5 GB saved" at approval. At 10 minutes, present a neutral optional summary: "You reviewed 18 photos. 7 are kept safe. 3 are ready in your tray. Nothing has been deleted." CTAs: Review tray / Keep reviewing / Done for now, with Done equally visible.

### Day 2 and week 1

When user voluntarily returns, show meaningful changes from locally known state: "8 new screenshot candidates in your selected scope", "2 new similar moments worth comparing", "3 rediscovered gems", or "Nothing urgent. Your last session is saved." Do not send notifications or badges by default; they are optional future requirements with separate explicit consent. A week-one local recap may show sessions completed, photos reviewed, kept/protected, albums organized, potential bytes seen, approved-to-tray and **confirmed logical bytes removed**. Do not assume a weekly streak or punish skipping. The app should be quiet and useful rather than habit-forming through guilt.

## C. Interaction specification and event semantics

```text
entry(intent?)
  ├─ demo -> local example decisions -> optional start real scan
  └─ real -> contextual authorization -> scoped scan or existing indexed results
      ├─ first meaningful result -> review/keep/protect/organize -> local receipt
      ├─ no candidate -> honest empty + alternative feature
      ├─ partial coverage -> show checked vs unavailable/unknown
      └─ denied -> demo + manage permission explanation

Review choice -> staged draft -> explicit Approve -> DeletionTray
DeletionTray -> explicit user request -> PhotoKit system confirmation -> reconcile
```

A first meaningful result is **not** time of an animation. Define `firstValueEvent` as one of: user explicitly kept a meaningful pair, created a durable user protection rule, successfully added a photo to Photos album, confirmed Favorite, completed a verified exact-duplicate review, or explicitly approved a removal to the tray. A demo first choice is measured separately as `demoFirstAction` and never mixed with real-library value. For active approval, zero deletions can still count as a successful session.

## D. Privacy-preserving local instrumentation

Do not add any vendor analytics network. If we instrument locally for user-visible statistics, define:

```swift
enum LocalImpactKind: String, Codable {
 case demoCompleted, photosIndexed, realReviewCompleted, keptBoth,
      protectionRuleCreated, albumAssignmentVerified, favoriteVerified,
      trayApproval, photoRemovalVerified, resumeAfterPause, resultsUnavailable
}
struct LocalImpactEvent: Codable, Sendable {
 let featureID: String
 let kind: LocalImpactKind
 let dayBucket: Int // local day or UTC epoch day, document timezone rule
 let elapsedMsBucket: Int?
 let countBucket: Int?
 let byteBucket: Int64?
}
```

No event contains asset IDs, exact timestamps, filenames, OCR, GPS, face metadata, photo content, precise dimensions or account IDs. Local impact data is under OS file protection and excluded from backup if it could be personal; make all event collection optional if possible, and expose deletion of local data. Export diagnostics is a **user-initiated** explicit action and must be scrubbed of photo-derived identifiers. A demo event is segregated from real metrics.

## E. Correct formulas

| Metric | Calculation | Limitation |
|---|---|---|
| Time to first demo action | monotonic elapsed time from demo shown to first choice | Not real-library performance |
| Time to first *real* value | app feature opened → confirmed meaningful user action | Dependent on authorization and scan scope |
| Review throughput | finished review decisions ÷ active foreground review minutes | Exclude paused/background time |
| Eligible potential bytes | sum unique eligible measured candidate resource sizes under known scope | Not capacity recovered; overlapping categories deduplicated |
| Tray-approved bytes | measured sizes for approved removal targets not yet committed | May become invalid/stale |
| Verified removed logical bytes | confirmed receipts after Photos re-fetch, excluding uncertain operations | Not local free-space or iCloud quota |
| Local available-capacity delta | OS available space after − before, if measurable | No causal attribution to our operation |
| iCloud quota recovered | **do not calculate / display as a numeric claim** | iCloud sync, shared libraries, Recently Deleted, Optimize Storage |
| Kept-safe count | unique currently protected target candidates in known scope | Counts only accessible, evaluated items |
| Coverage | indexed / analyzed / resource-verified / inaccessible / skipped counts by scope | Never claim global Photos completeness under limited access |

## F. Design experiment and acceptance plan

Conduct a small moderated usability panel (not simulated internal endorsement) on two iPhone sizes and iPad, each with sample and disposable authorized libraries. Tasks: find first useful card, Keep both, Protect a photo, make one exact-copy tray approval, explain whether anything was deleted, and find how to stop the session. Record time, wrong-direction swipes, accidental approval attempts, permission confusion and self-reported confidence. Proposed targets (to be measured): ≥90% correctly distinguish tray approval from deletion; zero destructive actions without two explicit approvals; first bundled-demo choice within 30s on reference device; 80% find Done for now unaided. Report results/uncertainty transparently, not manufactured success metrics.



---

<!-- Source: shared/06_TEST_AND_RELEASE_GATES.md -->

# Comprehensive tests, evaluation metrics and release gates

## 1. Test layers and exact commands

Source: observed root Makefile. On macOS with full supported Xcode and simulator:

```bash
xcode-select -p && xcodebuild -version
swift test --package-path Core
python3 -m unittest discover -s fixtures -p 'test_*.py'
make eval
make lint
make gen
make build
make ios-test
make budget BUDGET_TIER=M
```

On GitHub CI, use repository workflow and inspect actual run IDs. Do not equate a passing core test with PhotoKit integration or a simulated Vision inference skip with a hardware pass. The repository's existing `make ci` includes build/tests but does not necessarily perform device budget or on-device Photos canaries; run required gates separately. `make budget` may need a compatible iPhone SE simulator runtime; its memory model does not replace physical device sampling.

## 2. Safety mutation test fixture design

For each feature, construct injected `FakePhotoLibrary` and deterministically controlled time/task scheduler, then script these cases:

| Case | Injected event | Required behavior |
|---|---|---|
| R01 | Asset disappears after ranking | Pending removal stale; nothing deleted |
| R02 | Favorite toggled between approval and hashing | Commit blocked by fresh policy |
| R03 | Protection rule created during asynchronous digest | Commit blocked by final protection version |
| R04 | Keeper changed/removed | Target cannot proceed until new direct evidence |
| R05 | User cancels Photos prompt | No receipt of deletion; no space claim |
| R06 | Photos change request succeeds but app dies before reconciliation | Uncertain state, re-fetch, no automatic repeat |
| R07 | Limited library selection shrinks | Coverage decreases; unavailable items not reported deleted |
| R08 | Original exists only in iCloud | Default local-only; no network read; unknown reported |
| R09 | Media record has RAW, Live, edits, album protection | Conditional/hard policy remains enforced |
| R10 | One photo appears in multiple categories | Potential bytes counted once and no contradictory approvals |
| R11 | App thermal state serious | Checkpoint, visible pause, resumable cursor |
| R12 | SQL migration mid-backfill kill | Deterministic resume, no lost user protection or receipt |
| R13 | Corrupt cache/model payload | No crash; discard derived evidence, fail closed |
| R14 | iPad resize during draft, scan and tray | No duplicate work or mutation owner |
| R15 | Accessibility activation / repeated keyboard event | No duplicate approvals or surprise deletion |

The feature documents add named canaries; all apply in addition to the above. For any new PhotoKit mutation type (Favorite, album add, derivative create), add its own cancellation/uncertainty reconciliation tests. Zero direct deletion APIs outside established coordinator is a static gate.

## 3. Visual regression and human datasets

Synthetic fixtures should cover cases not present in natural datasets: one-digit screenshot change, changed QR, transitive similar graph, semantic differences in burst, same video opening with changed ending, hdr/audio drop, corrupted export, overlapping group and storage categories, and stale Photos revisions. Synthetic exact matches prove deterministic code paths, not real-world model performance.

For a human-rated consented dataset, separate train/calibration/validation/held-out test by **independent source moment**, not each frame or video as an independent example. Log collection policy, license, diversity of lighting/scene/device, annotator rubric, disagreement and exclusions. A go/no-go precision target requires an actual measured confidence interval. User preference agreement is not equal to harmful-deletion probability. Retain no private real photos in CI or public GitHub. The app's conservative deletion contract avoids auto-deletion for near matches regardless of classifier performance.

Suggested evaluation dimensions: candidate Recall@K, pair precision in "worth reviewing", calibrated uncertainty/abstention rate, multi-keeper uniqueness coverage, review throughput, false warning burden, 95% upper bound on unsafe auto-preselected exact removal opportunities, protected asset preservation, OS photo prompt integrity. Any statistic reported to users must have a defined denominator and scope.

## 4. Performance and device matrix

| Tier | Suggested reference | Must measure |
|---|---|---|
| Low supported iPhone | iPhone SE 2nd/3rd gen or iPhone 11 as supported OS permits | thermal, peak footprint, scan cancellation, AX text |
| Current iPhone | iPhone 17-class test device | Vision hardware behavior, 4K media, memory, power |
| Small iPad | iPad mini-supported OS | narrow/portrait/window resize, photo compare |
| Large iPad | iPad Pro-supported OS | side-by-side media rendering, keyboard/pointer, multitasking |

Do not claim simulated devices equal physical memory/thermal performance. Provisional engineering thresholds (subject to repository gate): main-thread stalling <250 ms, cancellation acknowledged within 2s at checkpoints, repeated 10k fake library scan retained-memory growth ≤10 MB, scan main actor work bounded, 250k-row SQLite paging with no O(N²) full comparisons. Final numeric peak memory must follow actual `DeviceTier`/`make budget` policy rather than an invented universal 300MB ceiling. Image decoder count and video frame sampling must be observable with local signposts/diagnostics.

## 5. Accessibility and multi-platform gates

Every user-visible feature: light/dark, landscape/portrait, AX3–AX5, Increase Contrast, Reduced Motion, VoiceOver, Full Keyboard Access, RTL and dynamic locale number/date format. Buttons >=44pt; never rely only on swipe/haptic/color. Real iPad tests include resizable Stage Manager narrow window, keyboard focus without accidental action, pointer hover nonmutating, and current one-window limitation. Verify simulator screenshots in repo's documented `make screens` workflow only when actual matching runner exists; record failures. Device photos and private screenshot content must never be uploaded to PR artifacts or public CI logs.

## 6. Privacy and architecture gates

Run `scripts/check_policy_separation.sh` and static scan for any new `deleteAssets` call, `URLSession`, unexpected PhotoKit network allowance, analytics SDK, background image upload or accidental raw OCR persistence. This is a code-review checklist in addition to scripted checks: a grep passing does not guarantee privacy. Inspect file data protection, backup exclusions, Keychain keys, app privacy manifest and Photos permission strings. All new models/assets must have redistributable commercial licenses verified prior to shipping; research-only pretrained weights are disallowed.

## 7. Required evidence in feature PR

- Exact HEAD SHA and diff scope, assigned migration version, user-visible feature flag default and rollback notes.
- Test results including explicit commands, exit codes, simulator/device OS and build identifiers.
- Negative-case fixture list with actual expected/observed outputs and any skipped/unavailable test.
- PhotoKit and safety review for any mutation path; code owner approval for safety changes.
- iPhone screenshots plus iPad compact/wide shots (no real personal photos).
- Performance traces for scope 100, 1k, 10k fake assets and physical device sample, with honest limitations.
- Local privacy scan; no upload/tracking endpoints; user-facing storage semantics audit.
- Definition of Done pass/fail with pending human gates clearly marked.

A green simulator build is necessary, not sufficient. Human owner must approve a TestFlight/public release independently after real-device deletion canaries and accuracy evidence.



---

<!-- Source: shared/07_DEPENDENCIES_AND_ROADMAP.md -->

# Dependency order, feature flags, build sequence and sustainability

## 1. Existing roadmap is a prerequisite

Before starting Nxx work, inspect real HEAD and `docs/VALIDATION_LOG.md`. In the verified README snapshot, F03 physical-device scan stability was still pending; source docs already have F04–F10 and S01 (Swipe n Save) work. Do not assume unmerged branches or pending device gates are complete. New feature implementation is **serialized**: one feature, tests, device gate, independent review, then next feature. Independent researchers/QA may investigate separate features, but production code integration stays ordered.

## 2. Suggested new feature order

| Stage | Feature | Why now | Blocking gate |
|---|---|---|---|
| 0 | Existing F03/S01 and necessary scoped-scan/first-run work | stable device behavior before new heavy inference | owner physical device |
| 1 | N05 Protection rules | protects all later new recommendation surfaces | safety coordinator and migration tests |
| 2 | N04 Storage goal planner | high value using cached evidence | N05 and accurate coverage/bytes |
| 3 | N07 Screenshot intelligence | visible first-session value at low media cost | OCR hard negatives and privacy |
| 4 | N06 Mistake Finder | explainable quality signals, human review | real quality evaluation |
| 5 | N01 Moment Intelligence | calibrated multi-keeper improvement | Vision device and unique-content tests |
| 6 | N02 Similar Video | large storage opportunities | codec/device and thermal validation |
| 7 | N03 Compression Lab | highest media mutation risk | transactional creation/rollback |
| 8 | N08 Album Inbox | nondestructive utility for no-duplicate users | permissions matrix and Photos write coordinator |
| 9 | N09 Rescue Gems | positive rediscovery and retention | diversity/quality data |
| 10 | N10 Local Taste | only useful after reliable decision history | consent/privacy/holdout proof |

This is a recommended sequencing plan, not a promise of delivery time. If the build remains blocked by F03 device stability, do not push new photo decode workers to production. Research and code on a non-shipping branch can proceed while protecting the release gate.

## 3. Milestones and rough effort

A single experienced Swift/iOS developer with AI assistance, plus owner physical-device testing, can *roughly* expect:

- **Month 1–2:** resolve existing device gates, N05 rules, N04 plan engine and initial UX; achieve a trustworthy first-value flow.
- **Month 3–4:** N07 OCR screenshot packs, N06 explainable quality, plus local usability tests.
- **Month 5–6:** N01 multi-keeper moment engine, human evaluation and iPad comparison polish.
- **Month 7–9:** N02 video duplicates and N03 safe compression trials, with substantial QA/device matrix.
- **Month 9–10:** N08 Album Inbox including limited-access fallback, album mutation tests.
- **Month 10–11:** N09 Rescue Gems and user feedback study.
- **Month 11–12+:** N10 opt-in personalization, ablations and release/maintenance hardening.

This estimate excludes App Store review delays, Apple developer account administration, real dataset collection complications, and any SDK/API changes. Engineering person-days in individual files are rough design effort, not guaranteed timelines. Compression may reasonably be postponed beyond year one if validation is incomplete.

## 4. Feature flag and rollback contract

All Nxx flags are compile-time/local flags default OFF until exact feature gates pass. Flags are not remotely fetched. A rollback hides presentation and stops background work, but **never** silently removes user protection rules, committed Photos-created assets, receipts or active trays. For protection rules, rollback must continue enforcing them or block deletion altogether until data can be safely read. For compression, rollback must retain and reconcile incomplete operation journal rows, never assume the original has been deleted. For Local Taste, rollback chooses neutral ranking. Migration scripts are append-only and never undo irreversible PhotoKit changes.

## 5. Zero-subscription economics

The core logic uses Apple system frameworks (PhotoKit, Vision, AVFoundation), locally bundled code and user-device compute. There is no recurring model inference bill, database hosting, photo-storage service, third-party content moderation or telemetry ingestion. Costs still exist: Apple Developer Program membership, hardware (Mac/iPhone/iPad), QA time, code-signing/CI runner minutes, potential model licensing if optional weights are introduced, support and maintenance. **Free to every user does not imply zero cost to the developer.** Prefer first-party Apple-hosted asset packs only for later opt-in model delivery on supported OS versions, with a no-download baseline. Do not build a feature that requires recurring paid infrastructure to function.

## 6. Agent handoff sequence

For each Nxx, one PR includes:

1. Confirm source and current stage, cite the Nxx spec.
2. Record the actual baseline test/CI state and explicit pending owner gates.
3. Write failing pure safety/domain tests before implementing functionality.
4. Implement and test versioned DB migration (after current HEAD's highest version).
5. Implement independent bounded service behind protocol + fake adapter.
6. Implement iPhone feature UX; screenshots and a11y.
7. Implement iPad feature UX separately using shared domain engine; screenshots and keyboard/pointer.
8. Connect only to existing PhotoKit permission and delete/tray services.
9. Measure latency/memory/thermal/privacy; negative/race tests; unresolved device gates.
10. Update validation logs and flag status; request gatekeeper review. No next feature until approved.

## 7. Success at one year

The app remains **permanently free** with no paywall, ads, accounts or photo uploads; most users can experience at least one benefit in the first session; destructive events remain explicitly user authorized and accurately reconciled; it works in iPhone compact and iPad wide/narrow windows; photos are never represented as cloud quota reclaimed without evidence. Shipping fewer high-quality features is preferable to violating those guarantees.



---

<!-- Source: shared/09_FEATURE_PARITY_MATRIX.md -->

# iPhone / iPad feature parity and shared-component ownership

| Feature | Shared engine / data | iPhone implementation | iPad implementation | Device-specific tests |
|---|---|---|---|---|
| N05 Protection | rule store, verdict gate, immutable safety policy | asset Protect sheet, rule list, shield chips | rules sidebar/list/inspector, keyboard search | album permissions; rule edit during pending deletion; iPad resize |
| N04 Storage Goal | planner, candidate overlap, potential-byte ledger | one-card review deck and goal chips | three-pane goal/candidate/compare workspace | goal preservation after rotate; byte VoiceOver |
| N07 Screenshot | screenshot candidate index, OCR guard, changed-text evidence | stacked screenshot compare, diff toggle | group grid + side-by-side zoomed diff | text changes; QR; OCR fallback; iPad synchronized pan |
| N06 Mistake | quality evidence, Issue enum, manual review | quality category cards, photo-first reason chips | issue sidebar, large image + signal inspector | artistic blur, low light; large image budget |
| N01 Moment | evidence graph, multi-keeper draft, parent review | swipe pair + keeper filmstrip + parent summary | filmstrip, dual compare, keeper inspector | transitive graph; 40-frame burst; keyboard actions |
| N02 Video | frame sampler, local alignment, resource checks | stacked dual players, duration/audio warning | simultaneous comparison timeline/inspector | HDR/audio/trim; thermal; focus |
| N03 Compression | capability validator, journal, export, create/reconcile | preset sheet, trial progress and before/after | job queue + side-by-side video + metadata | 4K/codec/low disk; crash after Photos save |
| N08 Album | album destination adapter, mutation reconciliation, local labels | album chips and single-item inbox | sidebar-album drag/drop grid inspector | limited access; idempotent Photos membership |
| N09 Gems | diversity ranker, batch history, Favorite mutation | full-screen gem carousel | mosaic + detail + time filter | diversity/time samples; Favorite invalidates tray |
| N10 Local Taste | opt-in samples, bounded ranker and held-out gate | settings, simple synthetic demo, ordering chip | standard-vs-personalized inspector | reset/opt-out, model corruption, focus and keyboard |

### Shared ownership rules

- `Core/`: pure algorithms, typed invariants, non-Photos rule/evidence models. No SwiftUI/Photos/AVFoundation dependency if possible.
- `App/Store/LibraryStore.swift`: single DB connection owner, migrations, cursor and feature caches. No new competing writer actor.
- `App/Services/PhotoLibraryClient.swift`: PhotoKit data access boundary; new features use capability-specific adapters over this boundary.
- `App/Services/ResourceGovernor.swift`: heavy-work scheduling. Screen size alone never multiplies worker concurrency.
- `App/Store/DeletionTray.swift` and `App/Services/PhotoDeletionCoordinator.swift`: **sole destructive path**. New screens can approve candidates, not bypass deletion guards.
- `App/Views/` and new `App/Views/iPad/` folders: separate compositions, shared tiles/chips/number formatters and view models where appropriate.
- `iOSTests/`, `UITests/`: code-level and user-flow tests on both device families. UI screenshots without real user photos.



---

<!-- Source: shared/08_COMPETITOR_EVIDENCE.md -->

# Competitor evidence registry — scope and confidence

**Research date:** November 12, 2026. These sources are public App Store/vendor descriptions from the prior deep-research exercise; they establish what an app **advertises**, not independent implementation details or verified algorithm accuracy. Availability, plan tiers and paywall placement change by country/time and must be rechecked immediately before publishing marketing comparisons. No claim here should be read as an endorsement.

| Product / source | User-visible marketed capability relevant to this spec | CleanSlate counterpart | Evidence category |
|---|---|---|---|
| [Flic: AI Photo & Video Cleaner](https://apps.apple.com/us/app/flic-ai-photo-video-cleaner/id918263212) | On-device assistance, likely junk, best shots, storage-goal plans, local preference learning, daily rediscovery, unlimited usage premium | N04/N01/N09/N10 | App Store advertiser description; specific premium gate is stated in listing |
| [CleanMyPhone](https://apps.apple.com/us/app/cleanmy-phone-cleanup-storage/id1277110040) | Similar/duplicate cleanup, compression, Live conversion, blurry/large media, Sensitive exclusion, iPhone/iPad, local image processing claim | N05/N06/N03 | App Store advertiser description |
| [Cleanup: Phone Storage Cleaner](https://apps.apple.com/us/app/cleanup-phone-storage-cleaner/id1510944943) | Duplicate photos/videos, similar screenshots, lookalike videos, best-photo marking, compression, broad utility bundle | N07/N02/N01/N03 | App Store advertiser description |
| [Cleaner Kit](https://apps.apple.com/us/app/cleaner-kit-clean-up-storage/id1194582243) | Duplicate/blurry detection and storage cleanup, Live Photo conversion | N06/N03 | App Store advertiser description |
| [Swipewipe](https://apps.apple.com/us/app/swipewipe-photo-cleaner/id1583884012) | Month-by-month swipe cleanup, On This Day, streaks, screenshots and blurry grouping | S01/N09/onboarding | App Store advertiser description; we intentionally reject coercive streaks |
| [Slidebox](https://apps.apple.com/us/app/slidebox-photo-cleaner-app/id984305203) | Album sorting, swipes, favorites, undo, progress, iPhone/iPad | N08 | App Store advertiser description |
| [Clever Cleaner](https://apps.apple.com/us/app/clever-cleaner-ai-cleanup-app/id1666645584) | Best Shot, similar groups, skip/protect lists, compression and swipe | N05/N01 | App Store advertiser description; price/free claims can vary by storefront |
| [Cleansmith](https://apps.apple.com/us/app/cleansmith-photo-cleaner/id926090192) | Similar video search, low-resolution/closed-eye classes, compression, Live Photo and spatial media | N02/N06/N03 | App Store advertiser description; CleanSlate does not claim eye-state accuracy |
| [Apple Photos Duplicates support](https://support.apple.com/en-us/104967) | Apple's own Photos deletion and duplicate workflow; Recently Deleted/iCloud implications | All | First-party Apple support; third-party PhotoKit does not expose a generic native duplicate-merge call |
| [Apple PhotoKit limited access](https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app) | Restricted album operations under limited library authorization | N05/N08 | First-party Apple API guidance |
| [Apple Vision text](https://developer.apple.com/documentation/vision/recognizing-text-in-images) | On-device OCR interface | N07 | First-party developer docs |
| [Apple Vision image feature prints](https://developer.apple.com/documentation/Vision/GenerateImageFeaturePrintRequest) | Visual descriptor comparison interface | N01/N02 | First-party developer docs |
| [Apple Vision image aesthetics](https://developer.apple.com/documentation/Vision/CalculateImageAestheticsScoresRequest) | Technical aesthetic scoring | N01/N06/N09 | First-party developer docs; not subjective memory worth |
| [Apple AVAssetImageGenerator](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator) | Extract selected frames from video assets | N02 | First-party developer docs |
| [Apple AVAssetExportSession](https://developer.apple.com/documentation/AVFoundation/AVAssetExportSession) | Supported local media export | N03 | First-party developer docs |
| [Apple PhotoKit change requests](https://developer.apple.com/documentation/photokit/requesting-changes-to-the-photo-library) | Public API for user-authorized mutations | N03/N08/N09 | First-party developer docs |

## Claims we are NOT making

- No unverified current US subscription price/plan is treated as timeless; research showed some price points but exact screens vary.
- No reverse-engineered competitor algorithm, accuracy rate, actual retention number or independent privacy audit is asserted.
- 'On-device' in a competitor listing is a marketing claim unless confirmed by independent technical evidence.
- No inference that competitor subscription compute requires servers; many relevant functions can run on-device and be charged for as a business model.
- No implication that CleanSlate provides Apple's first-party duplicate *merge*, restores permanently deleted items, or controls iCloud quota storage.

## Research conclusions translated into requirements

1. Paid market monetizes throughput, guided prioritization and convenience. **N04** supplies a free transparent planner without speculative recovery claims.
2. Paid market uses "Best" labels. **N01** uses multi-keeper review and abstention so it doesn't destroy distinct memories.
3. Screenshot and video intelligence deliver high perceived savings. **N07/N02** require actual changed-content guards and bounded device work.
4. Compression is enticing but risky. **N03** stores a verified *copy* before any separate original-deletion review.
5. Swipe interaction can be habit forming. Existing S01 plus first-session contract deliver fluency without streak pressure, countdowns or paywalls.
6. Positive rediscovery and sorting matter even with zero duplicates. **N08/N09** ensure cleaning isn't the only way to succeed.
7. Personalization can be private. **N10** starts off and is constrained to ranking, never safety policy.



---

<!-- Source: features/N05-protection-rules.md -->

# N05 — Never Suggest / Protected Rules

**Maturity:** proposed implementation specification, **not** in the released app. **Priority:** foundational first of new features. **Effort:** M, ~8–15 engineer-days excluding physical-device certification. **Paid-market analogues:** CleanMyPhone's Sensitive photos exclusion and Clever Cleaner's Skip List (vendor-advertised, not independently audited). **Critical dependency:** existing safety policy and human approval before changing deletion eligibility.

## 1. Product contract and first-use benefit

A user must be able to say **"Don't recommend deleting this photo (or anything in this album/date range)"** and trust that the rule applies in suggestions, swipe workflows, goal plans, screenshot reviews, video cleaning and the final commit. The feature is protective, not a replacement for Apple's Hidden album or biometric vault. A user can choose rules per individual asset, existing user album (when full Photos authorization allows it), and inclusive local-date interval. Default behavior when an album disappears, Photos access is restricted or rule evaluation is unavailable is **fail closed for affected pending deletion drafts**, never silently convert to a deletable state.

**First 30 seconds:** a bundled synthetic gallery shows a birthday picture with a "Protect" button. Tapping it locks the item and immediately removes its simulated deletion suggestion, changing an explanation from "Possible duplicate" to "Kept safe by your rule". No permission or real photo is touched. With library access, long-press a real photo or select it in a group → Protect → choose *Only this photo*, *This date range*, or *This album* (album option shown only if supported) → confirm → immediately update eligible queue and tray warnings. The prompt says "Protected here, not in Apple Photos; your original stays where it is."

**Non-goals:** hide photos from other apps; encrypt Photos itself; biometric vault; keep backups; bulk-delete with inverse rules; promise iCloud synchronization of CleanSlate rules; infer sensitive categories by analyzing faces/sexuality; protect all photos of a person via face recognition.

## 2. Behavior and domain rules

Protection evaluation order:

1. Native immutable `PreservationFlag.hard` safety and permission restrictions.
2. Explicit per-asset user protection rule.
3. Applicable album/date user protection rule; if album membership cannot currently be evaluated for a pending removal, mark **indeterminate**, not unprotected.
4. Existing conditional RAW/Live/edited preservation policy and keeper equivalence rules.
5. Optional category-level "do not suggest" preference (a recommendation filter, not a hard security rule).

Distinguish **hard block** (prevent any removal from CleanSlate), **hide suggestions** (item may remain a visible keeper but never a removal proposal), and **dismissed once** (suppress a suggestion in current revision until next explicit scan). The first two are durable local user intent. When an asset is protected, pending exact approvals using it as a removal target become `needsAttention`; a protected surviving keeper can stay in the group. Unprotect does NOT automatically restore a former deletion decision. Rules are active immediately after durable storage commit and before UI refresh. Disabling a rule requires deliberate selection and confirmation explaining consequences.

Protection records must NOT be confused with a fake metadata flag. The deletion coordinator must consume authoritative protection results at both planning and **fresh pre-PhotoKit commit**; this is a safety-path change and requires owner review, mutation tests and regression evidence. Do not add another `deleteAssets` site. A serialized `ProtectionGate` resolves active rules and pauses any in-flight commit if the rule-set version changes between validation and mutation. The app cannot guard against changes in Apple's Photos library between devices other than existing PhotoKit revalidation.

## 3. Proposed schema and migration

Append this after the highest *actual* migration present at implementation time:

```sql
CREATE TABLE protection_rules(
  rule_id TEXT PRIMARY KEY,
  kind TEXT NOT NULL CHECK(kind IN ('asset','album','date_range')),
  target_id TEXT,                    -- PHAsset or PHAssetCollection ID, local and opaque
  start_local_day TEXT, end_local_day TEXT, -- YYYY-MM-DD inclusive displayed local calendar
  calendar_id TEXT, time_zone_id TEXT,
  created_at REAL NOT NULL, updated_at REAL NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  rule_version INTEGER NOT NULL DEFAULT 1,
  CHECK((kind='asset' AND target_id IS NOT NULL) OR
        (kind='album' AND target_id IS NOT NULL) OR
        (kind='date_range' AND start_local_day IS NOT NULL AND end_local_day IS NOT NULL))
);
CREATE INDEX protection_active_by_target ON protection_rules(kind,target_id) WHERE enabled=1;
CREATE TABLE protection_rule_revision(singleton INTEGER PRIMARY KEY CHECK(singleton=1), revision INTEGER NOT NULL);
INSERT INTO protection_rule_revision VALUES (1,1);
```

Only opaque PhotoKit IDs, user-selected interval and rule metadata are stored. Avoid persisting full album title, user-provided text reason or thumbnails. If custom labels are later added, treat them as personal data, encrypted by system data protection and never exported by default. When a rule is deleted, keep no tombstone with the old target ID after purge; group reviews referencing that rule are invalidated via global revision. The rule service should store a UTC-resolved interval for comparison after choosing a calendar/time zone, while retaining the original calendar/date for human-readable display. DST transitions and missing creation dates require explicit tests.

## 4. Swift contracts and data flow

```swift
enum ProtectionScope: Codable, Sendable {
    case asset(localIdentifier: String)
    case album(localIdentifier: String)
    case dateRange(startInclusive: Date, endExclusive: Date,
                   calendarID: String, timeZoneID: String)
}
enum ProtectionVerdict: Sendable, Equatable {
    case protected(ruleIDs: Set<UUID>)
    case unprotected(ruleSetVersion: Int64)
    case indeterminate(reason: String)
}
protocol ProtectionEvaluating: Sendable {
    func verdict(asset: PhotoSnapshot, albumIDs: Set<String>?,
                 permission: PhotoAuthorizationScope) async -> ProtectionVerdict
    func currentVersion() async -> Int64
}
actor ProtectionRuleStore {
    func set(_ scope: ProtectionScope, enabled: Bool) async throws -> Int64
    func remove(ruleID: UUID) async throws -> Int64
    func rules(after cursor: String?, limit: Int) async throws -> [ProtectionRule]
}
```

These types are **interface proposals**, not statements that they currently compile against the repository. Implement the authorization scope adapter using actual PhotoKit permissions. `ProtectionRuleStore` can be an extension to `LibraryStore` if its single-connection actor remains authoritative; don't open a second SQLite writer. UI obtains `ProtectionVerdict` from a single application service. During deletion, existing coordinator must call protection evaluation using **fresh** snapshots/album membership immediately before PhotoKit changes, detect rule revision changes, and abort if protected/indeterminate. If the existing PhotoKit client already marks user albums as a hard protection, do not accidentally weaken that blanket policy when introducing user-defined album rules.

**State machine:** `notProtected → ruleSaving → protected → editPending → protected/removed` with `error` and `permissionLimited` substates. `pendingDelete → invalidatedByRule → needsReview`. A failed write leaves UI unprotected with a truthful error; never show a green shield before durable commit. `protected → unprotected` requires explicit action and does not reactivate old tray entries.

## 5. iPhone UX — exact screens

**Review action sheet:** a shield icon/label "Protect" adjacent to Keep/Skip. Tapping opens a bottom sheet with options: Only this photo (always supported), Date range (show currently matched count within authorized scope, computed locally), Current album (only with full access and known album), Cancel. Show example warning: "This will block CleanSlate from suggesting deletion of matching items. It does not prevent deletion in Photos." Confirm applies rule and announces "Protected" with Undo *rule creation* (not photo deletion).

**Protected Rules screen:** `Settings → Protected photos and rules`; counts of active rules, three tabs Asset / Albums / Date ranges, each with name/interval, coverage badge and edit/off controls. If count is large, search **by rule type** but never show camera roll thumbnails without permission. `Show affected` lists accessible current matching items, paginated. In limited mode, album rules show "Unavailable while Photos access is limited; pending approvals are held" with a button to manage selected photos. Disable creates no automatic deletion proposals.

**Review group:** protected candidates stay visible with lock badge and accessible reason. A protected candidate's Delete button is disabled; if user tries a swipe that would remove it, show "Protected by your rule" and offer "Keep" or "View rule". A protected keeper stays a valid keeper, and the group may offer fewer removal candidates. No intrusive rule creation pop-up after a user says Keep both.

**First session:** demo appears before authorization; for real value, show one rule matched to current accessible photo in under three taps. No false count for unavailable albums or cloud-only media.

## 6. iPad UX — separately implementable

Wide windows: Rules sidebar with Asset / Album / Date sections, central rule list and detail inspector on right, including the current permitted coverage and affected preview grid. Toolbar + keyboard shortcuts must respect focus; Command-F searches rules, Escape closes editor, no shortcut to disable all protections. Narrow Stage Manager windows collapse to the phone sheet; preserve edit draft and scroll position across resize. Pointer context menu offers Protect asset, View existing rule and Cancel. Dragging photos into a rule list may be considered **later** only if it cannot bypass confirmation or leak a PhotoKit asset ID across app boundaries. VoiceOver reads "Protected photo, rule: selected date range, cannot be proposed for deletion"; touch/keyboard/VoiceOver all use the same service call.

## 7. Edge cases and threat analysis

- Edited photo changes revision: asset rule keyed by stable local ID persists; a cached image-specific preview must be reloaded. Different logical asset ID after export/reimport is a different asset and does not inherit rules silently.
- Favorite/unfavorite does not change a user rule. Native favorite protection still applies independently.
- Date range across DST, travel time zones, unknown creation date, iCloud original missing: never convert unknown to a protection match or a deletion opportunity without explicit review. For a *date-range* rule unknown date means no match; a pending deletion whose full safety evaluation depends on missing date becomes indeterminate.
- Album renamed: stable album ID remains rule target. Album deleted or limited access: state unavailable and block affected pending approvals when membership cannot be resolved; do not claim rule currently protects every asset.
- Simultaneous rule edit and delete: serialize through app-level action gate or detect rule version changes and fail before mutation; stress test with task barriers.
- SQLite DB corrupted/deleted: no protection rules could be read; block new removal approvals until user acknowledges recovery or rebuilds rules. Never silently treat absent DB as intentional clearing of all rules.
- Only user-selected photos under limited access are visible; summary must say "among X accessible photos".
- iPad and iPhone may have different local rule sets without CleanSlate account sync; do not promise cross-device protection parity.

## 8. Verification, fixtures and acceptance criteria

Fixture pack: 1 exact group with protected target; 1 similar group with protected keeper; 1 date-boundary group; 1 asset favorited while rule is being saved; 1 album renamed after rule creation; 1 simulated limited-permission selection change; 1 concurrent `commit` and protect write. Use synthetic PHAsset-like records/fakes for policy tests; physical-device PhotoKit album cases require a disposable Photos library.

```gherkin
Scenario: Protection invalidates an already approved deletion
  Given a byte-verified duplicate is in the deletion tray
  When I protect the candidate asset
  Then the tray entry is marked Needs Attention before any PhotoKit deletion call
  And the candidate is not removed from Photos

Scenario: Protection changes after asynchronous full-resource hashing
  Given deletion verification is reading original resources
  When a protection rule is created for the candidate
  Then the final protection-version check blocks the commit
  And no mutation of Photos occurs

Scenario: Limited authorization cannot establish album membership
  Given the user only granted limited Photos access
  And album-level rule evaluation is unavailable
  When a pending candidate could be affected by an album rule
  Then the approval cannot advance to deletion
  And an explanation offers management of Photos access

Scenario: Removing a rule does not resurrect an old approval
  Given an old tray entry was invalidated by a protection rule
  When I disable the rule
  Then the old entry still requires a new explicit review
```

**Tests:** Core pure precedence matrix (hard flag, conditional flag, user asset rule, album rule, date rule); SQL migration/rollback; crash between rule write and UI acknowledgment; commit-race mutation; album access matrix; iPhone VoiceOver and AX5; iPad resize/focus; cancellation; `make lint` policy separation. Physical-device gate confirms actual album APIs, system permission dialogs and cross-device iCloud deletion warnings.

**Local measurements:** `protectedRulesCreated`, `candidateApprovalsInvalidated`, `rulesDisabled`, `coverageUnknown` (aggregated counts only). No exact protected Photo IDs in analytics. Acceptance is zero protected target deletions in all mutation tests, complete explanations for unknown rules, and a successful permission-free demo. Sign-off requires owner approval of any safety-coordinator change.

## 9. Suggested commits and rollback

1. `N05.1`: add failing Core tests for protection precedence; pure verdict types.
2. `N05.2`: append `LibraryStore` migration, rule CRUD and migration tests.
3. `N05.3`: implement `ProtectionEvaluator`, revision invalidation and coordinator checks **with explicit safety review**.
4. `N05.4`: wire iPhone action sheet/rule list + fake fixtures.
5. `N05.5`: adaptive iPad rule inspector, keyboard/pointer/a11y.
6. `N05.6`: crash/race/device gate, local counters, release note.

Feature flag `N05ProtectionRulesEnabled` defaults OFF until verification; disabling it after rules exist must **not** discard the rule checks in deletion coordinator (fail closed), only hide new rule creation UI. Rollback disables UI/features while continuing to block commits dependent on unknown rule state. Do not downgrade schema in place.

**Definition of Done:** documented active-rule precedence, protected-target canary passes, no new delete call, old tray invalidation verified, migration replay passes, limited-access album behavior truthful, iPhone/iPad AX tests complete, real-device safety sign-off recorded.

**Sources:** https://apps.apple.com/us/app/cleanmy-phone-cleanup-storage/id1277110040 ; https://apps.apple.com/us/app/clever-cleaner-ai-cleanup-app/id1666645584 ; https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app ; https://github.com/rishiehari/cleanslate/blob/main/Core/Sources/CleanSlateCore/SafetyPolicy.swift



---

<!-- Source: features/N04-storage-goal-planner.md -->

# N04 — Evidence-Based Storage Goal Planner

**Priority:** second new feature, after N05. **Estimate:** M, ~9–15 engineer-days with existing index/coverage in place. **Premium counterpart:** Flic markets goal-oriented cleanup for X GB; this is an advertised product capability, not evidence of its implementation algorithm. **Requirement:** a credible plan built *only* from already known, eligible media; never promise that a chosen target is reachable or actually free after Photos confirmation.

## 1. User story and precision of promise

A user sees an iPhone storage warning and wants "Help me find about 2 GB I can review safely" rather than manually opening every category. The app presents a staged plan: exact verified copies first, then screenshots/large videos/manual similar reviews, with risk, review cost and **known/unknown bytes**. Every item remains a user review action. The product may select an efficient review order, not make deletion decisions.

The first visual state is a demo based on bundled examples: goal 1 GB; 150 MB known exact copies; 600 MB large video for review; 200 MB screenshot group; 50 MB unknown. The UI explicitly says "950 MB possible from these examples — not yet freed" and allows the user to compare the plan. Users can choose an actual goal (`500 MB`, `1 GB`, `2 GB`, `5 GB`, Custom), only after checking current authorized index coverage. No actual 'fastest way to free X GB' claim until measured evidence exists.

A real plan can have less known potential than the goal, and should celebrate the honesty: "We found 620 MB worth reviewing in the 100 photos checked. More may be available if you scan more." If current results are zero, offer a nondestructive action (Rescue Gems/Album Inbox) rather than implying a broken scan.

**Non-goals:** changing Photos Optimize Storage, clearing Recently Deleted automatically, claiming iCloud quota recovery, optimizing device caches, guessing compressed sizes, forcing the user toward a deletion quota, deleting an original simply to hit a target, silently scanning the whole library.

## 2. Planning model

Represent the goal and partial evidence separately:

```swift
struct StorageGoal: Codable, Sendable {
    let id: UUID
    let targetLogicalBytes: Int64 // user request, NOT free-space promise
    let scopeID: String          // selected authorized scan scope
    let createdAt: Date
}
struct PlanCandidate: Identifiable, Sendable {
    let id: String
    let assetIDs: [String]
    let expectedRevisions: [String: String]
    let kind: PlanKind             // verifiedExact, screenshots, largeVideo, similarReview
    let potentialBytes: Int64?    // nil if unknown
    let evidenceStatus: EvidenceStatus
    let knownProtected: Bool
    let reviewCostSecondsEstimate: Int? // UI may omit until calibrated
    let generation: Int
}
struct GoalPlan: Sendable {
    let items: [PlanCandidate]
    let potentialKnownBytes: Int64
    let unknownCount: Int
    let coverage: CoverageDescriptor
    let attainableFromKnownEvidence: Bool
}
protocol StoragePlanBuilding: Sendable {
    func build(goal: StorageGoal, scope: ScopeDescriptor,
               cursor: String?, maxItems: Int) async throws -> GoalPlan
}
```

`EvidenceStatus` and `CoverageDescriptor` are shared proposed types: implement once in an adapter, do not add duplicative enums across screens. Candidate byte weights must avoid double-counting an asset appearing in an exact group, screenshot category and large-files list. Distinct candidates are grouped by stable `asset_id` and revision. A group deletion benefit is only the sum of eligible **reviewed prospective targets**, not total group bytes. Do not treat a protected asset as a candidate to remove. For a similar group, count bytes only after manual selection or label them **review opportunity, amount not yet eligible**; never imply model decided which to remove.

## 3. Deterministic algorithm and complexity

Inputs are paginated SQLite candidates with current safety/protection checks and cached byte evidence. Stage 1: de-duplicate asset references and skip stale/protected/unauthorized items. Stage 2: partition into conservative tiers:

- Tier A: complete byte-verified exact duplicates with eligible keeper evidence and measured target resource sizes.
- Tier B: standalone screenshots/screens recordings/large files that require user inspection (size may be known).
- Tier C: similar groups without a user decision (zero guaranteed potential; surface as later work, not counted toward target).
- Tier D: compression candidate estimates, only if N03 implemented; present separate range or experiment and exclude from known total.

Within tiers, sort by useful known bytes descending, then estimated review friction ascending, then stable opaque ID for deterministic paging. The algorithm is a **review queue selector**, not a knapsack optimizing destructive outcomes. Stop when known *potential* (not confirmed recovered) meets user target or scope exhausted; return `unmet` with explicit coverage. Number of candidate rows processed is bounded by scope cap and pagination (target O(N log K) heap selection for top K; bounded K; no media decoding in planning). Because candidates can overlap, maintain a `Set<assetID>` only up to bounded page/block and persist processed identifiers in a database cursor/table if the collection is large. Deterministic replay requires the same index generation; invalidated index forces rebuild, not stale reuse.

```text
build(goal, scope):
  ensure permission and scope are current
  iterate stable paged candidate index
    reject stale, user-protected or unverified-ownership items
    compute potential bytes ONLY from valid resource evidence
    deduplicate candidate target references across category sources
    add to risk-tier queue; track unknown coverage separately
  emit ordered review-only plan with achievedPotential and unattainableReason
```

## 4. Local persistence

```sql
CREATE TABLE storage_goals(
 id TEXT PRIMARY KEY, target_bytes INTEGER NOT NULL CHECK(target_bytes>0),
 scope_id TEXT NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL,
 state TEXT NOT NULL CHECK(state IN ('draft','active','paused','completed','cancelled')),
 index_generation INTEGER NOT NULL
);
CREATE TABLE storage_goal_items(
 goal_id TEXT NOT NULL REFERENCES storage_goals(id) ON DELETE CASCADE,
 item_id TEXT NOT NULL, asset_id TEXT NOT NULL,
 asset_revision TEXT NOT NULL, evidence_version INTEGER NOT NULL,
 rank INTEGER NOT NULL, status TEXT NOT NULL,
 known_potential_bytes INTEGER,
 PRIMARY KEY(goal_id,item_id,asset_id)
);
CREATE INDEX goal_items_order ON storage_goal_items(goal_id,rank);
```

Store planned references, not images. Goal progress is user decisions (reviewed, approved, system-confirmed) and cannot be inferred from an old selected flag. On app resume or authorization changes, use the current `LibraryStore` generation and `ProtectionRuleStore` revision to mark stale items. Progress receipts remain separate from simulated potential bytes.

**State machine:** `demo → goalChosen → planning → readyPartial/readyComplete → reviewing → awaitingUserApproval → trayReady → reconciliation → completed/paused`. At any point `permissionsChanged`, `libraryChanged`, `scanCancelled`, `offlineOriginal`, `goalUnreachable` must preserve user goal but not reapprove anything. After a Photos deletion, reconcile success into receipts. If user stops early or chooses Keep both, display progress in **decisions completed**, not "savings achieved".

## 5. iPhone screen-by-screen implementation

**Entry/Home:** small "Plan a cleanup" card with your last selected goal (if any) and "What this means" disclosure. Tapping opens Goal Picker: chips 500 MB/1/2/5 GB, custom numeric field with locale-aware units, subtitle "We'll find items for you to review; no photos are deleted automatically." The demo is available as secondary CTA without Photos permission.

**Coverage check:** if F04 Recent-100 exists, default to that documented scope. If only a full/partial index exists, display real state: "Indexed 1,340 accessible items; verified sizes for 100; 24 pending". Give user explicit *Use what you've checked* and *Scan more* actions; don't quietly launch a huge scan.

**Plan card stack:** top shows goal, *known potential*, *unknown/unverified*, *verified removed from completed deletion receipts*, and user decisions count. Each card displays category, evidence badge, photo/video thumbnail (unless unavailable), bytes if verified, direct keeper context for exact groups and **Review**. After review, Add to tray uses existing approval flow. Header uses "X MB ready for review" rather than "Space you'll free".

**End state:** "Reviewed 18 items · Approved 6 · Confirmed removed 4 (312 MB logical file bytes)." Show "Some items remain in Recently Deleted". Offer Done or Continue, no quota pressure or confetti for deleting. If goal unmet, explain known/unknown; don't generate made-up recommendations.

## 6. iPad screen-by-screen implementation

Use category/goal sidebar on left, plan list center with byte evidence/risk/coverage columns, review comparison on right. Wide window can show a sticky header goal meter with **separate segments**: known potential, confirmed removed and unverified (not additive to free space). Row selection opens existing group/standalone review without closing context; approval updates row to "In tray" but leaves review queue navigable. Keyboard Up/Down moves plan cursor, Return opens review; it never confirms deletion. Pointer hover previews category, not a destructive action. On narrow Stage Manager window collapse to iPhone deck; one plan and tray coordinator persist across resizing. Accessibility narrates absolute numbers and semantics, not color-only bars.

## 7. Safety/privacy/performance/edge cases

- A goal can exceed known candidates: state unmet, optionally offer scoped scan.
- Two candidate groups share a target: asset counted once and never approved in contradictory keeper sets; use existing tray overlap guard.
- A target becomes favorite or protected: remove from eligible known potential; invalidate pending row and tray entry.
- Size becomes unavailable or original is cloud-only: show unknown; no zero-byte fabricated size; default does not download originals.
- Multi-resource Live/RAW or edits: rely on full-resource digests and current safety flags. Do not infer logical bytes from primary JPEG alone.
- PhotoKit deletion canceled by user: goal remains active, receipts unchanged.
- iCloud sync or Recently Deleted: never equate logical bytes with free device space or iCloud quota.
- SQLite index partially rebuilt: force plan generation version mismatch and show Rebuild; do not render old potential as current.
- O(N²) plan assembly and repeated thumbnails are unacceptable. Planning uses SQL metadata and lazy visible image loading.

## 8. Acceptance tests and demo

Fixture: 2 exact groups (total 140 MB known), overlapping screenshot group (same asset counted once), 1 protected 50 MB photo, 1 300 MB video with unknown local size, 1 similar group with unique-expression difference, 1 inaccessible iCloud-only resource, 1 user approval canceled at OS prompt. Start the demo with user choosing a 500 MB goal; show honest "140 MB verified for review, more unknown" and no pending deletion. After approved deletion receipt the confirmed counter advances independently of known potential.

```gherkin
Scenario: A plan never double-counts overlapping candidates
 Given a verified exact duplicate is also a screenshot and a large file
 When I build a 1 GB goal plan
 Then its logical bytes appear at most once in the known-potential total
 And all review routes lead to the same underlying asset and revision

Scenario: The user cancels Apple's Photos confirmation
 Given 250 MB is approved in the deletion tray
 When the Photos confirmation is cancelled
 Then verified removed logical bytes remain unchanged
 And the goal continues to say 'potential' rather than 'freed'

Scenario: An unavailable iCloud original has no verified size
 Given the asset is visible as a thumbnail but the original is not local
 When I generate a plan without opting into iCloud original downloads
 Then the asset is counted as unknown, not as zero or guessed bytes

Scenario: A protected target becomes unavailable for planning
 Given a plan item references an asset newly protected by N05
 When the plan is resumed
 Then the item is invalidated
 And it cannot be approved to the deletion tray
```

**Tests:** pure queue ordering/overlap; migration and schema integrity; partial scope accuracy; 250k-row fake SQLite benchmark without media decode; UI first goal/cancel/resume; iPad narrow-to-wide preservation; protection race; currency/locale byte formatting; full Photos prompt on disposable device; AX reading of progress segments. Proposed target: build first plan from 10k cached candidates without a frame stall and show initial seeded/demonstration value in under 30s; measure device performance before asserting success.

**Local counters:** `goalOpened`, `goalCreated`, `planReady`, `reviewOpened`, `itemsReviewed`, `goalAbandoned`, `verifiedLogicalBytesRemoved`, `unavailableCandidateCount`, with date/time bucket and no asset identifiers. Never upload.

## 9. Implementation commits, tests, rollback

1. `N04.1` shared domain types and fail-closed pure-plan fixtures.
2. `N04.2` append `LibraryStore` goal tables and paginated candidate-query adapter; migration tests.
3. `N04.3` build deterministic tiering and overlap resolver; 250k metadata benchmark.
4. `N04.4` add iPhone goal picker/demo/review queue using existing tray.
5. `N04.5` add iPad plan list/detail, keyboard, accessibility.
6. `N04.6` add local metrics, receipt reconciliation, stale refresh and device checks.

Suggested paths `Core/Sources/CleanSlateCore/StoragePlan.swift`, `App/Services/StorageGoalPlanner.swift`, `App/Views/StorageGoalView.swift`, `App/Views/iPad/StoragePlanWorkspace.swift`, `iOSTests/StoragePlanTests.swift`, `UITests/StorageGoalFlowUITests.swift`. Adjust to repo structure; add no new deletion endpoint.

Flag `N04StoragePlannerEnabled` defaults OFF until gates pass. Rollback hides goal UI but retains user-approved tray and actual receipts. Old goal records are inert after flag off; never alter deletions. Definition of Done: correct disjoint potential calculation, truthful coverage and receipt semantics, 250k metadata perf pass, iPhone/iPad interaction/evidence, protection/permission tests, no Photos writes outside existing flow.

**Sources:** https://apps.apple.com/us/app/flic-ai-photo-video-cleaner/id918263212 ; https://support.apple.com/en-us/104967 ; https://developer.apple.com/documentation/photos/phassetresourcerequestoptions/isnetworkaccessallowed ; https://github.com/rishiehari/cleanslate/blob/main/App/Store/LibraryStore.swift



---

<!-- Source: features/N07-screenshot-intelligence.md -->

# N07 — Screenshot Intelligence: repeat detection, changed-text protection, and review packs

**Feature class:** advanced on-device grouping atop existing screenshots category. **Effort:** L, roughly 14–23 engineer-days plus privacy review. **Premium analogues:** Cleanup/CleanMyPhone/Flic market screenshot cleanup and intelligent sorting; the exact OCR safety method here is CleanSlate's design, not a proven vendor implementation. **Dependencies:** F04 scoped indexing/F05 progress, N05 protection, N04 goal planning as optional consumer.

## 1. Outcome and human-centered requirements

The basic screenshots list already exists in CleanSlate. N07's incremental promise is **help me find screenshots that are visually repeated without accidentally discarding changed information**. Typical cases: duplicate login instructions, receipts, event details, chat screenshots, maps/directions, ticket QR codes and a screenshot of an updated delivery ETA. A visually similar screenshot containing a different gate, seat, time, price, OTP, tracking number or message must remain **distinct** even if global image embedding similarity is very high.

A demo group of four synthetic ticket screenshots illustrates the benefit before Photos permission: images 1 and 2 are byte/near-render duplicates; image 3 has a new boarding gate; image 4 has different QR data. Present 1–2 as one review group; label 3–4 "Important changes detected — kept separate". User can try Compare and Keep both; no simulated action touches Photos. A truthful empty state says "No repeated screenshots found in the items checked" and offers age/month or large-file sorting, not "All your screenshots are junk."

N07 must not be a general semantic understanding chatbot and must not label a screenshot "unimportant" based on content alone. Do not extract contact data, OTPs, medical records or transaction amounts for any cloud model. No OCR text search or external classification in V1. All decisions are review-only, and standalone screenshot deletion uses the existing manual approval tray.

## 2. Classification pipeline and exact stages

**Stage A, inventory:** select only assets with PhotoKit `PHAssetMediaSubtype.photoScreenshot` under the current authorization scope. Optionally include screen recordings in a separate category; never decode video frames in screenshot worker. Paginate descending by date using `LibraryStore`, with scope revisions. Do not identify screenshots solely from filenames.

**Stage B, cheap candidate hashing:** request a local downscaled raster (target e.g. 256px max axis with documented quality), compute perceptual/difference hash and aspect/resolution bucket. Nearby time and same pixel dimensions are *candidate hints*, not proof. Use hash band indices to find a bounded candidate set; no O(N²) all screenshots comparison.

**Stage C, OCR guard:** for each candidate pair (not the entire library indiscriminately), perform Vision text recognition offline. Extract bounding rectangles, language probability where exposed, normalized text lines and high-entropy token categories **in ephemeral memory**. Normalization may fold whitespace and punctuation but must NOT fold digits, currency, addresses, URLs, codes, dates, times or alphanumeric tokens. A conservative changed-text guard rejects equivalence if salient text differs. Distinguish OCR unknown from OCR equal; unknown requires manual review without a redundancy badge. Use Vision `VNRecognizeTextRequest` or supported Swift `RecognizeTextRequest` after SDK validation; do not assume a simulated Vision request works on every runtime.

**Stage D, structural comparison:** align images using aspect ratio and small transforms; compare hashes/feature prints plus text rectangle overlap. If text is confidently identical *and* image geometry is close, form a **possible repeated screenshot** group. If text differs or OCR confidence is poor, show a paired comparison labeled "Review differences" or keep separate. QR/barcodes contain meaningful changes that OCR may miss: V1 detects high-contrast block differences and always abstains from duplicate qualification when such regions differ; do not pretend to decode all QR content. Future Vision barcode detection requires separate tests/permissions/accuracy gate.

**Stage E, user experience:** generate pairwise evidence of screenshot relation, not a blanket group edge. A group of 3 uses a keeper set only if every proposed removal has direct evidence to a surviving keeper. Similar screenshot groups are NEVER preselected. Exact byte-equal resources may use existing exact flow, with normal protection checks.

Illustrative rule (not statistically calibrated): `candidate = dHashBucketsOverlap && aspectWithinTolerance`, `reviewSimilar = visualDistanceWithinConfiguredBound && !salientTextDifference && !barcodeDifference`, `confirmedExact = ResourceSignatures.canonical(allResources) equality`. Thresholds live in versioned configuration and must be calibrated on hard negatives. Log counts of unknown OCR separately; no hard-coded '90% safe' claim.

## 3. Data model and persistence

```sql
CREATE TABLE screenshot_features(
 asset_id TEXT NOT NULL, revision TEXT NOT NULL, algorithm_version INTEGER NOT NULL,
 screenshot_kind TEXT NOT NULL CHECK(screenshot_kind IN ('image','recording')),
 phash_bands BLOB,
 text_hmac BLOB,             -- keyed digest ONLY; not raw OCR
 text_block_count INTEGER,
 high_entropy_token_count INTEGER,
 text_confidence_bucket INTEGER,
 text_change_guard INTEGER NOT NULL DEFAULT 0,
 barcode_sensitive INTEGER NOT NULL DEFAULT 0,
 status TEXT NOT NULL CHECK(status IN ('ready','unavailable','failed','stale')),
 updated_at REAL NOT NULL,
 PRIMARY KEY(asset_id,revision,algorithm_version)
);
CREATE INDEX screenshot_status ON screenshot_features(status,updated_at);
CREATE TABLE screenshot_review_edges(
 id TEXT PRIMARY KEY, left_asset_id TEXT NOT NULL, right_asset_id TEXT NOT NULL,
 left_revision TEXT NOT NULL, right_revision TEXT NOT NULL,
 evidence_kind TEXT NOT NULL, algorithm_version INTEGER NOT NULL,
 review_only INTEGER NOT NULL DEFAULT 1, created_at REAL NOT NULL
);
CREATE INDEX screenshot_edge_left ON screenshot_review_edges(left_asset_id);
```

Use a **per-install Keychain secret** to HMAC canonical text fingerprints. If secret changes or unavailable, invalidate/regenerate the fingerprints; do not write plaintext OCR as fallback. HMAC equality indicates normalized line text equality, not screenshot resource equivalence; line order/bounding box also matters. Protection flags must be considered at every display/approval. Logs store only counts and coarse durations, never text length as a unique fingerprint in diagnostics. By default store no recognized strings, bounding-box text pairs, or image crops on disk. Group edges cache invalidates on either revision or OCR version change.

## 4. Proposed Swift interfaces

```swift
struct ScreenshotCandidateKey: Sendable {
  let assetID: String
  let revision: String
  let aspectBucket: Int
  let hashBands: [UInt16]
}
struct SalientTextEvidence: Sendable {
  let normalizedTextHMAC: Data? // nil on unknown
  let blockCount: Int
  let criticalDifference: Bool
  let confidenceClass: OCRConfidenceClass
  let barcodeStructureChanged: Bool
}
enum ScreenshotRelation: Sendable {
  case byteIdentical
  case visualAndTextMatchForReview
  case changedInformation
  case inconclusive
}
protocol ScreenshotAnalyzing: Sendable {
  func candidateKey(_ image: CGImage, revision: String) async throws -> ScreenshotCandidateKey
  func textEvidence(_ image: CGImage) async throws -> SalientTextEvidence
  func compare(_ left: ScreenshotAnalysis, _ right: ScreenshotAnalysis) -> ScreenshotRelation
}
actor ScreenshotIndexCoordinator {
  func analyze(scope: ScopeDescriptor, cursor: String?) async throws -> ScreenshotProgress
  func reviewGroups(after cursor: String?, limit: Int) async -> [ScreenshotReviewGroup]
}
```

Use `@MainActor PhotoLibraryClient` only to acquire authorized thumbnails; expensive raster processing occurs off main with bounded concurrency and autorelease pools. `ScreenshotIndexCoordinator` persists ephemeral evidence into `LibraryStore` via an extension, not a separate writer. OCR may fail because of scripts/language/low contrast; failure is `inconclusive`, never text equality. Expose `recognitionLanguages` and revision as settings only if testing supports them; keep bilingual canaries.

**State machine:** `notIndexed → candidatesFound → comparing → reviewReady/changedInformation/unknown → reviewed/keptBoth/trayApproved` and independent `paused/stale/failed` substates. A new Photos screenshot inserted while scanning is discovered via next incremental inventory, not by restarting all OCR. If scanner stops at 500, coverage explicitly says 500 checked.

## 5. iPhone UX design

**Screen 1, category overview:** Screenshot Intelligence card appears below existing screenshot category, showing "27 repeated-looking screenshots to review" plus "6 with changed text kept separate" **only if measured in current scope**. If no OCR has run, display "Analyze repeated screenshots" with scan scope and expected local-only processing disclaimer. No pushy storage goal.

**Screen 2, review packs:** segmented controls "Repeated", "Changed info", "All"; each pack shows overlapped thumbnails and badges "Possible repetition"/"Important text may differ". The latter is a warning, not a claim the text is unimportant. Tap a pack for compare. A monthly filter is optional; all counts use permitted scope.

**Screen 3, difference compare:** two full-width screenshots stacked on narrow phones, pinch zoom with a dedicated Diff toggle. When diff is active, overlay bounding rectangles for changed regions computed transiently; do not persist text snapshots. If OCR uncertain, say "We couldn't compare every word. Check both images." Buttons: Keep left, Keep both, Keep right, Protect, Skip. Destructive choice is not approved until the separate Approve action, then tray. Never show a single "Delete all old screenshots" shortcut.

**Screen 4, result:** "Reviewed 8 screenshot pairs · 3 items ready in tray · 4 different information sets preserved". If user kept both, count as a successful review. View tray is optional; Done for now prominent.

## 6. iPad UX design

Sidebar has screenshot categories (Repeat candidates, Changed info, By month, Unchecked); main pane uses dense pack gallery with enough context to identify screen contents; detail pane compares side-by-side with synchronized zoom and a transient diff overlay. Pointer can hover to reveal Compare but cannot stage deletion; keyboard arrow keys switch pack, `K` optional for Keep both *only when focused review*, Escape returns to pack. Narrow Stage Manager windows collapse to phone-style compare; OCR work does not double when two panes request a pack. VoiceOver provides "Possible similar screenshot. Some text differs" plus a count of changed regions, never reads sensitive OCR text by default. A user may explicitly use system text recognition on their visible screenshot through the accessibility system; CleanSlate does not store those recognized strings.

## 7. Security, performance and failure cases

- OCR containing passwords, financial IDs, codes, health data, private chats: discard plaintext after processing and apply OS data protection to derived cache.
- Recompressed screenshot loses exact bytes but not visible content: still manual review; no exact label.
- Text differs by one digit (flight gate, price, OTP): preserve as changed information even when a hashing heuristic considers them close.
- Same text, changed QR code, photo or chart: preserve; OCR equality isn't enough.
- Different languages or no OCR coverage: inconclusive, show side-by-side, no automatic pair elimination.
- Screenshot in Live Photo or edited asset oddity: existing conditional protection applies.
- Permission revoked between OCR and review: invalidate and hide thumbs; do not show cached raw screenshots.
- Photo appears in protected album: respect existing hard album protection and N05.
- Performance: bounded local thumbnails, one OCR worker on low tier, model cache evicted on memory warning, governor checkpoint after each candidate group, cancellation every asset. Large-screenshot count may be >50k, but pair generation must use hash buckets and limited probes, not all pairs.

## 8. Gherkin, test plan and physical-device gate

```gherkin
Scenario: Single-digit difference blocks a repeated-screenshot claim
 Given two image-identical boarding passes differ only by gate "B12" versus "B13"
 When Screenshot Intelligence compares them
 Then evidence is changedInformation or inconclusive, not equivalent
 And neither photo is preselected to remove

Scenario: OCR cannot read a low-contrast screenshot
 Given a valid screenshot with unreadable text
 When OCR fails or confidence is below the validated gate
 Then the result remains reviewOnly with an uncertainty explanation

Scenario: User keeps both sides of a repeated pair
 Given a displayed screenshot pair
 When the user selects Keep both
 Then no item is added to the tray
 And the local session counts one completed review

Scenario: Permission revoked between analysis and approval
 Given a cached screenshot review pack
 When Photos authorization is revoked
 Then approval is blocked, previews are cleared and scope is marked stale
```

**Fixtures:** exact PNG pair, compressed JPEG version, one-digit change, different QR pixel blocks, multiline receipt with changed total, night-mode color inversion, right-to-left mixed-language screenshot, very small text, screenshot containing a person photo, scrolling long screenshot. Test different color spaces and cropped overlaps. Human-label 100+ realistic screenshot families only with proper consent; record precision/review burden without exporting private OCR. Unittest comparator and HMAC secret reset; integration SQLite keys + migration; iOS Vision OCR on device; UI demo/changed-text warning/AX5, iPad diff pan/resize; memory soak 10k fake assets.

Proposed go/no-go: **zero unsupported automatic screenshot deletions** (by construction), no plaintext OCR persisted, changed-digit and changed-barcode canaries always fail closed, generator and scan progress/cancel reproducible, core synthetic and user-rated hard negatives evaluated. No release claim of OCR accuracy without representative real data.

## 9. Implementation commits, switches and fallback

1. N07.1 pure typed evidence and negative test corpus.
2. N07.2 screenshot feature table, Keychain HMAC service, migration and purge test.
3. N07.3 bounded Vision OCR adapter and changed-token guard with cancellation.
4. N07.4 retrieval/grouping/revision invalidation and real coverage accounting.
5. N07.5 iPhone packs/diff and existing tray integration.
6. N07.6 iPad multi-pane compare, keyboard/pointer/VoiceOver.
7. N07.7 field validation and privacy/security review.

Suggested files: `Core/Sources/CleanSlateCore/ScreenshotEvidence.swift`, `App/Services/ScreenshotAnalyzer.swift`, `App/Services/ScreenshotFeatureStore.swift` (prefer `LibraryStore` extension), `App/Views/ScreenshotIntelligenceView.swift`, `App/Views/iPad/ScreenshotWorkspace.swift`, `iOSTests/ScreenshotEvidenceTests.swift`, `UITests/ScreenshotReviewUITests.swift`. `N07Enabled` OFF until gates; rollback disables classifier and preserves manual screenshot list. Never remove source Photos assets or encrypted cache keys as part of feature rollback; local reset is explicit.

**Sources:** https://developer.apple.com/documentation/vision/recognizing-text-in-images ; https://apps.apple.com/us/app/cleanup-phone-storage-cleaner/id1510944943 ; https://apps.apple.com/us/app/cleanmy-phone-cleanup-storage/id1277110040 ; https://github.com/rishiehari/cleanslate/blob/main/App/Models/PhotoModels.swift



---

<!-- Source: features/N06-mistake-finder.md -->

# N06 — Mistake Finder: evidence-based blur, exposure and tiny-image review

**Priority:** after screenshot intelligence. **Effort:** M, ~10–18 engineer-days plus ranking evaluation. **Premium analogues:** CleanMyPhone/Cleaner Kit blur categories and Cleansmith low-resolution/closed-eye marketing. **Hard boundary:** do not advertise reliable "closed eyes" or "bad photo" detection without a separately validated dedicated model; user taste and meaningful memories override generic technical metrics.

## 1. User problem and first-value interaction

Photos that were accidental, badly blurred, unusably dark or only tiny previews can consume space and clutter searches. A user wants a **low-confidence review queue with explanations**, not an automated machine judging whether family memories are valuable. First use before Photos permission presents a four-image demonstration: motion blur, intentionally shallow depth of field portrait, very dark exposure, sharp photo. It labels the blur and dark images "Review suggestion" and explicitly keeps the artistic portrait out of automatic mistakes. Each demo card has Why?/Keep/Review and is clearly synthetic.

With authorization, Mistake Finder analyzes a chosen scope and shows a cautious set of review packs: "Possibly blurry", "Very small", "Possibly over-/underexposed", optionally "Needs a second look". If everything is excellent or unknown, celebrate: "No obvious issues found in this scope" and direct to other value. **Never** use terms like "trash"/"ugly" as categorical quality facts. All deletion choices are manual, and suggestions never enter the tray without an explicit photo inspection and approval.

## 2. Evidence architecture

Instead of one opaque rank, compute independent technical signals:

- **Sharpness:** downscaled luminance gradient or variance of Laplacian with scale-aware normalization. Distinguish a global motion-blur pattern from low-detail scenes by checking edge count; low edge count alone is **not** proof of blur.
- **Exposure:** luminance histogram fractions near clipping; average luminance with high-dynamic-range caution; avoid marking night skies or silhouettes as mistakes solely due to darkness.
- **Resolution:** source pixel dimensions from PhotoKit, not thumbnail dimensions; flag strongly reduced copies only against device/media expectations and preserve intentional thumbnails/art.
- **Face capture quality:** Vision's quality request provides a technical indicator if supported; do not infer identity, attractiveness, emotion, eye openness or uniqueness. If no face is detectable, no face penalty.
- **Aesthetic scores:** optional tie-break/display insight only, not deletability. Do not interpret it as intrinsic artistic worth.

Each signal produces `measurement`, `validity`, `reasonCode`, `uncertainty`. A classifier eligibility gate requires multiple independently meaningful signals OR an extreme single issue with calibrated evidence; any artifact/artistic scene ambiguity triggers `reviewOnly` or `notFlagged`. There is **no automatic deletion** even for high-confidence blur. Maintain explicit issue codes, not a combined undocumented score.

```swift
enum QualityIssue: String, Codable, Sendable {
 case possibleMotionBlur, exposureClipping, lowPixelResolution,
      weakFaceCaptureQuality, insufficientEvidence
}
struct QualitySignal: Codable, Sendable {
 let issue: QualityIssue
 let metricValue: Double?
 let thresholdVersion: Int
 let validity: SignalValidity
 let reviewSuggested: Bool
}
struct MistakeFinding: Sendable {
 let assetID: String
 let revision: String
 let signals: [QualitySignal]
 let shouldAppearInReview: Bool
 let automaticRemovalAllowed: Bool // ALWAYS false
}
protocol PhotoQualityAnalyzing: Sendable {
 func analyzeThumbnail(_ image: CGImage, sourceWidth: Int,
                      sourceHeight: Int, revision: String) async throws -> [QualitySignal]
}
```

The analyzer may consume `QualitySignals` already computed by the existing `App/Services/VisualAnalyzing.swift` and keeper ranker; don't rerun full Vision work if valid cached evidence exists. Cache per asset+revision+signalVersion+inputResolution. Avoid long CPU/GPU work on the main actor; UIImage/CGImage buffers are released each batch. For low-memory tier, one photo at a time until measured proof otherwise.

## 3. Proposed persistence and state

```sql
CREATE TABLE quality_issue_cache(
 asset_id TEXT NOT NULL, revision TEXT NOT NULL, algorithm_version INTEGER NOT NULL,
 source_width INTEGER NOT NULL, source_height INTEGER NOT NULL,
 signal_payload_json TEXT NOT NULL,
 analyzed_at REAL NOT NULL,
 status TEXT NOT NULL CHECK(status IN ('ready','unavailable','failed')),
 PRIMARY KEY(asset_id,revision,algorithm_version)
);
CREATE INDEX quality_issue_status ON quality_issue_cache(status,analyzed_at);
CREATE TABLE quality_review_state(
 asset_id TEXT NOT NULL, revision TEXT NOT NULL,
 state TEXT NOT NULL CHECK(state IN ('unreviewed','kept','approved_to_tray','dismissed')),
 decided_at REAL, PRIMARY KEY(asset_id,revision)
);
```

Persist only coarse numeric signals and issue codes; no face embeddings/crops or original photos. Local explicit dismissals override future queue ordering for that revision. On a photo edit, old quality result is stale and must be recomputed; new revision must not inherit a prior deletion choice. `QualityIssue` values need stable versioning and locale-independent machine identifiers. `JSON` field requires schema version, size limit, strict decode and corrupted-row fallback.

**State machine:** `eligible → analyzing → findingsReady/unknown/noIssues → reviewChosen → kept/dismissed/trayApproved`; `pause/thermal/permissionLost/revisionChanged` can interrupt analysis, leaving a resumable cursor. An 'approved to tray' action is not deletion; only existing tray has commit authority.

## 4. iPhone UX — separate design

Home card appears only after usable signals or as a contextual demo. The category view uses three vertically stacked quality groups with actual counts within current scan coverage. Each entry's hero image is a photo plus concise reason chips: "Possible motion blur", "Very dark", "640×480 original". Tap opens Compare with nearby moment frames if a group exists, otherwise single-photo review. An intentional silhouette may be marked "Keep; this is intentional" which suppresses quality warnings for the same asset revision. A visible Why? detail explains the numeric signal in ordinary words and its limitations, e.g. "This photo has few sharp edges; intentional soft focus can look similar." Never show a bogus universal 0–100 quality truth score.

The bottom primary actions are Keep, Review later, Protect, Add to tray (only after explicit review). The app does not force a Keep/Delete binary for a solo photo. When it has a sharper nearby alternative, show both and let the human choose multiple keepers; N01 owns multi-keeper intelligence. End of session: "10 photos checked · 3 kept · 2 ready in tray · 5 skipped". Do not say "2 failures removed" before confirmation.

## 5. iPad UX — adaptive, not a stretched list

Left pane lists issue categories and counts; middle pane is a browsable grid with filter chips; right pane shows a large photo/optional alternate at a resolution suitable for seeing blur. A fixed detail panel displays each signal with confidence/limitations and a one-click Keep/Protect/Review control. Pointer hover can reveal metadata; keyboard focus changes selected photo but not approval. `K` may Keep, `P` Protect, Escape closes inspector only after shortcut conflict review; no Delete shortcut. Side-by-side comparison has linked zoom and a visible reset. Stage Manager narrow widths move categories into a sheet and detail full-screen, preserving review draft. VoiceOver reads "Possible blur (not confirmed); user review required" before actions; accessibility control order remains photo → explanation → safe actions.

## 6. Quality evaluation and difficult cases

Real-world quality tests must deliberately include artistic motion blur, bokeh portraits, dim candles, night sky, fireworks, intentional grain, screenshots, panorama, macro, animated/Live media and cropped tiny icons. Avoid bias from skin tones/face exposure; measure false suggestions across diverse lighting and faces. Develop with public-domain/self-made images, then human-label a consented representative photo sample. Annotation question: "Would you want to be *shown* this for review?" not "Should an AI delete this?" Agreement and disagreement are reported; use a reserved holdout. A person may deliberately keep a blurry photo as their only memory of an event; favorite, album, edited and user protection rules remain absolute.

Use a cost/benefit gate: feature is useful only if users find meaningful candidates at a false-alert burden that does not overwhelm; acceptance thresholds are hypotheses pending data (e.g. precision of 'worth reviewing' ≥0.8 on held-out annotation, with confidence bounds). A lower-quality photo with **no verified alternative** must never be preselected, irrespective of score. No model is trained on personal photo labels or uploaded data by default.

## 7. Functional requirements and test scenarios

```gherkin
Scenario: Artistic blur does not imply deletion
 Given a deliberately shallow-depth portrait with a soft background
 When Mistake Finder analyzes the image
 Then any warning is described as a possible issue, not a deletion fact
 And automaticRemovalAllowed is false
 And no image is staged without explicit user review

Scenario: Source resolution is independent of preview size
 Given a 4032x3024 original rendered in a 256px preview
 When resolution quality is calculated
 Then source dimensions are used
 And the photo is not called low-resolution because of the preview

Scenario: No usable quality evidence
 Given Vision and raster analysis both fail for an iCloud-only image
 When the quality review queue is refreshed
 Then its status is unknown or skipped
 And its inability to be evaluated is included in coverage

Scenario: User marks warning irrelevant
 Given a dark photo was shown as 'possibly very dark'
 When the user chooses Keep and dismiss warning
 Then the same asset revision is not re-suggested in the active review scope
 And a subsequent edit may trigger a new evidence version but not an automatic removal
```

**Fixture matrix:** full blur vs structured low-detail, tiny source vs tiny preview, intentional silhouette vs failed exposure, overexposed light source vs washed-out scene, face visible vs obstructed, mismatched color profiles, Live/RAW/adjusted, corrupted thumbnail, scene with no face. Unit metric normalization; iOS Vision fallbacks; SQL migration; batching/thermal/timeout; stale revisions; limited authorization; iPhone/iPad AX5/dark mode; device color/exposure render; end-to-end manual selection/Photos prompt cancellation with disposable library.

## 8. Performance, privacy, metrics and rollout

Reuse photo feature cache; prohibit full-resolution decode for ordinary scans. Limit quality evaluation to a scope the user explicitly initiated, with progress shown. On thermal pressure, checkpoint and pause with reason. Target one asset in flight on lowest device tier and no retained UIImage beyond iteration. Never store face images, embeddings or identification. On a low-powered device, return initial partial results rather than running an invisible 250k-asset quality audit.

Local aggregates: `qualityAssetsAnalyzed`, `reviewSuggestionsShown`, `keptFromMistakeReview`, `warningsDismissed`, `approvedToTray`, `signalUnavailableCount`. Measure helpfulness via on-device optional thumb feedback, but do not send metrics off device. Compare utility vs warning false-positive burden in supervised device tests; never show made-up accuracy badges.

Suggested commits: `N06.1` pure metrics/tests; `N06.2` bounded analysis/reuse feature cache; `N06.3` cache migration/state; `N06.4` iPhone; `N06.5` iPad; `N06.6` held-out quality test + device gates. Paths: `Core/Sources/CleanSlateCore/QualityIssue.swift`, `App/Services/MistakeFinder.swift`, `App/Views/MistakeFinderView.swift`, `App/Views/iPad/MistakeWorkspace.swift`, `iOSTests/MistakeFinderTests.swift`, `UITests/MistakeFinderUITests.swift`. Flag `N06Enabled` OFF until evaluation. Rollback deletes only rebuildable issue cache by explicit migration/maintenance, not Photos assets or real deletion receipts.

**Done:** zero silent additions to deletion tray, transparent issue reasons, meaningful no-results path, quality canaries and real-image holdout documented, Swift+UI+device budgets satisfied, iPad parity verified, no changes to safety constants.

**Sources:** https://developer.apple.com/documentation/Vision/CalculateImageAestheticsScoresRequest ; https://developer.apple.com/documentation/vision/detectfacecapturequalityrequest ; https://apps.apple.com/us/app/cleansmith-photo-cleaner/id926090192 ; https://apps.apple.com/us/app/cleanmy-phone-cleanup-storage/id1277110040



---

<!-- Source: features/N01-moment-intelligence.md -->

# N01 — Moment Intelligence / Best-Shot+ with multiple keepers

**Priority:** after trust, scoped scans, screenshot/quality foundations. **Effort:** XL, ~20–35 engineer-days plus independently collected evaluation data; model-quality gate may take longer. **Competitive analogue:** "Best shot" and similar/burst selection from Flic, Clever Cleaner and CleanMyPhone. **Distinctiveness:** preserve materially different moments, not merely the highest numerical quality image. **Absolute rule:** similar photos are manual review and never preselected for deletion.

## 1. First-use product promise

People shoot ten frames of a child jumping, a group portrait or a birthday cake. Two images may be sharper, but different frames show different smiles, expressions, subjects or composition. CleanSlate's value is a curated review explanation: **"You may want to keep these two, not just one."** This is advice, not proof that every memory is represented. A first-run synthetic example shows 5 frames: a sharp solo smile, one group hug, a blink, a similar but softer solo smile and a unique candle-blowing frame. The safe starting keeper set contains at least the solo, hug and candle frames; no one is removed without user review.

In a real library, users enter from existing Similar/Bursts/Swipe n Save cards. If evidence is unavailable, show all photos and let them choose; never ask the user to wait for all Vision work before seeing anything. Do not use face identification, emotional state, attractiveness, or a claim to know which photo is "the most meaningful". Favor human control: Keep multiple, Compare, Protect, Skip, Undo staged choices, and clear review state.

## 2. Architecture: candidate groups versus deletion evidence

**Stage 1 — candidate moment grouping.** Use actual PhotoKit `burstIdentifier` where available, otherwise bounded temporal cohorts + capture dimensions + cheap fingerprints. Time proximity alone means "may be from one moment", not visual redundancy. Avoid joining different events or creating 100,000 all-pairs edges. Group construction is a *UI organizer*, not a deletion authority.

**Stage 2 — pairwise analysis.** For a bounded candidate cluster, request local thumbnails (e.g. 320px analysis / higher only for on-screen comparison). Compute existing Vision `GenerateImageFeaturePrintRequest` distance, `DifferenceHash`, sharpness/exposure signals, optional face rectangles/face-capture quality, and spatial change regions. Feature-print errors are first-class errors; current repository notes simulator Vision model failures, requiring real-device validation. Never equate a feature-distance threshold with a calibrated probability until tested.

**Stage 3 — uniqueness guard.** Material differences may be: a subject entered/exited frame; different face arrangement; distinct pose; object/cake/candle changes; different focal region; changed text/sign; camera framing. A robust V1 can only flag *possible* uniqueness through alignment and change heatmaps plus temporal spacing. When uniqueness cannot be determined, set `requiresManualComparison`. Group size and coverage remain visible; no hidden auto-exclusion.

**Stage 4 — quality ranking.** For each photo, compute valid technical quality signals with distinct provenance: sharpness, clipped exposure, source fidelity/resolution, Vision face-capture quality if supported, aesthetics if available, blur consistency. Convert each to normalized scores only with a documented version and empirical calibration. A disabled/unavailable signal gets no fake zero. A very sharp image cannot outrank a protected keeper for safety decisions.

**Stage 5 — constrained multi-keeper selection for display.** Mandatory keepers: protected/native hard flags, current user favorites, explicit user Keep choices and assets not shown/compared. Construct a coverage graph where an edge means *candidate-level similarity*, not safe removability. Add diversity representatives until uncovered subjects/crops/times are represented to a documented heuristic. This yields a **suggested view order and initial keeper highlights**, not a suggested deletion set. A displayed thumbnail marked "Suggested keeper" is not a safety override. For every eventual target removal, the existing direct pair evidence to a surviving keeper is required by `SafetyPolicy` and the user's explicit review.

**Optimization objective (for suggestions only):** maximize technical quality and coverage of distinct visual compositions with a bounded number of highlighted frames, but retain all nonselected frames as **undecided** until human review. Avoid winner-takes-all tournaments; if A~B, B~C but A differs from C, keep a representative of A and C. In a large burst (e.g. 40 frames), split into cards but preserve parent cluster and staged decisions atomically.

## 3. Domain model / suggested Swift signatures

```swift
struct MomentID: Hashable, Codable, Sendable { let value: String }
struct MomentMember: Sendable {
 let assetID: String
 let revision: String
 let capturedAt: Date?
 let userKeep: Bool
 let protection: ProtectionVerdict
 let quality: [QualitySignal]
}
enum PairProvenance: String, Codable, Sendable {
 case photoKitBurst, visuallyCompared, temporalCandidate, exactResources
}
struct MomentPairEvidence: Sendable {
 let leftID: String; let rightID: String
 let leftRevision: String; let rightRevision: String
 let provenance: PairProvenance
 let visualDistance: Float?
 let possibleUniqueContent: Bool
 let evidenceVersion: Int
}
struct MomentDraft: Sendable {
 let groupID: MomentID
 let memberRevisions: [String:String]
 let keepIDs: Set<String>
 let explicitlyReviewedRemoveIDs: Set<String>
 let undecidedIDs: Set<String>
}
protocol MomentPlanning: Sendable {
 func groups(in scope: ScopeDescriptor, after cursor: String?, limit: Int) async -> [MomentSummary]
 func analyze(_ group: MomentID, budget: AnalysisBudget) async throws -> MomentEvidence
 func suggestKeepers(_ evidence: MomentEvidence, explicitKeepers: Set<String>) -> Set<String>
}
```

`MomentDraft` is local presentation intent; only after every selected removal was displayed/explicitly reviewed and the whole parent group is summarized can a `PhotoReviewGroup`/existing tray entry be created. Do not pass `temporalCandidate` as `.verifiedNearDuplicate` into `SafetyPolicy`. Add a typed edge provenance bridge rather than assuming `near-*`/`seq-*` ID prefixes imply Vision verification (the existing Swipe plan warns about this limitation).

**State machine:** `candidateGroup → loadingVisibleFrames → comparing → draft(incomplete) → finalSummary → explicitlyApprovedToTray → awaitingCommit/committed`. `keepBoth`, `skip`, `protect`, `undo`, `pause`, `staleRevision` never bypass parent summary. If another queued action would remove an earlier keeper, recompute direct coverage and mark dependent removals undecided. A group containing protected photos cannot have them as deletion targets; if the whole group is unknown, show no recommended removals.

## 4. Proposed SQL, indexes and stale evidence

```sql
CREATE TABLE moment_groups(
 group_id TEXT PRIMARY KEY, cohort_key TEXT NOT NULL,
 group_version INTEGER NOT NULL, evidence_version INTEGER NOT NULL,
 created_at REAL NOT NULL, updated_at REAL NOT NULL,
 state TEXT NOT NULL CHECK(state IN ('candidate','analyzed','partial','stale'))
);
CREATE TABLE moment_members(
 group_id TEXT NOT NULL REFERENCES moment_groups(group_id) ON DELETE CASCADE,
 asset_id TEXT NOT NULL, asset_revision TEXT NOT NULL,
 display_rank INTEGER NOT NULL, suggested_keeper INTEGER NOT NULL DEFAULT 0,
 PRIMARY KEY(group_id,asset_id)
);
CREATE INDEX moment_member_asset ON moment_members(asset_id);
CREATE TABLE moment_edges(
 group_id TEXT NOT NULL REFERENCES moment_groups(group_id) ON DELETE CASCADE,
 left_asset_id TEXT NOT NULL, right_asset_id TEXT NOT NULL,
 left_revision TEXT NOT NULL, right_revision TEXT NOT NULL,
 relation TEXT NOT NULL, possible_unique INTEGER NOT NULL,
 evidence_version INTEGER NOT NULL,
 PRIMARY KEY(group_id,left_asset_id,right_asset_id)
);
CREATE TABLE moment_drafts(
 group_id TEXT PRIMARY KEY, draft_json TEXT NOT NULL, updated_at REAL NOT NULL,
 group_version INTEGER NOT NULL
);
```

Canonicalize pair IDs (`min(assetID), max(assetID)`) to avoid duplicate edges. Persist only evidence numbers/flags/revision, not face crops, facial identities or raw images. `moment_drafts` may contain asset IDs and human decisions but no Photos authority token. On library change, invalidate affected edges and draft; retain user intention as an *unapproved draft* only after rereading valid members, never recreate deleted photos. A group split/merge should transfer explicit kept IDs only through stable revision matching; removals revert to undecided.

## 5. iPhone screens: precise UI

**Moment card:** thumbnail mosaic with count and label "12 photos from the same moment" when burst metadata supports it; otherwise "12 nearby captures—check before deciding". A "Suggested keepers: 3" badge only after actual heuristic output; the interface never says "9 safe to delete".

**Comparison session:** one pair or triad at a time, always display source photos large enough to see faces. Bottom choices include Keep left, Keep both, Keep right, Compare zoom, Protect, Skip. Swipe semantics are the already defined S01 semantics and only **stage** a selection. On choice advance, show a temporary toast "Choice saved to draft · Nothing deleted". Some frames may have a tag "Different expression" / "Different composition" only when supported by measurable evidence; otherwise "May show something different".

**Keeper filmstrip:** fixed bottom carousel with current kept images highlighted and total "3 kept · 4 undecided"; tapping opens a full-screen comparison. If changing a keeper invalidates prior remover dependencies, show a non-dismissable review banner and clear unsafe removal marks.

**Parent summary:** full grid partitioned into Keeping / You selected to remove / Unreviewed, with explicit alternatives and protection badges. Disable Approve when any selected removal lacks a direct keeper edge or was never displayed. A disabled explanation links to the missing pair comparison. On approval, add a **single group-level** tray entry with frozen revisions; no PhotoKit mutation. On Done for now, save unapproved draft.

## 6. iPad screens and input model

Use a 3-pane moment workspace when wide: moment list sidebar, full filmstrip/canvas center, keeper set inspector at right. Side-by-side photos use synced zoom/pan, `Compare crops` shows face/body regions only transiently; no face images persisted. A 40-image burst becomes a scrollable filmstrip with one clear active compare, not 40 huge `UIImage`s. Resizing to half width collapses inspector without losing draft. Pointer highlights group/keeper options; dragging images into a Keep area is allowed only as a staged local decision and has accessible button equivalent. Keyboard: arrow keys navigate filmstrip, Left/Right/Up resolve current pair only when compare is focused, Command-Z undoes draft; pressing Delete never adds to tray. Full Keyboard Access and VoiceOver use named actions and announce "3 of 12 photos kept; 2 need review".

## 7. Hard cases and quality validation

Required negative examples: child smile vs cry, eyes open vs closed (don't claim detection unless validated), candle lit vs blown, person joining/leaving, a sign with changed text, pet changing pose, long fireworks exposure, panorama sweep, rapidly changing lighting, Live Photo frames, RAW/edited JPEG variants, burst with no metadata, three-image transitivity trap, near-identical images of different people, 40-member group exceeding budget, and intentionally soft artistic photo. Evaluate group precision (same actual moment), good-keeper coverage, average human review time, harmful deletion suggestion (must be zero by construction), and human agreement with highlighted keeper **set** rather than only top-1 rank.

A human-rated set must include diverse scenes/skin tones/low light and a counterbalanced holdout. Proposed launch target (not a result): ≥90% of annotated "must keep" distinct frames appear among suggested keeper set or receive explicit human review before removal, and zero observed unsafe automatic selection. Evaluate confidence intervals on independent moment groups, not each correlated frame as a separate trial. User overrides may adjust display order only under N10; not change safety evidence.

## 8. Acceptance Gherkin and tests

```gherkin
Scenario: A-B and B-C similarity does not erase a unique A-C difference
 Given frames A, B, C where A resembles B, B resembles C, but A is distinct from C
 When Moment Intelligence proposes a keeper set
 Then no removal is considered proven by a transitive path
 And A and C may both remain as keepers
 And every staged removal requires direct comparison to a surviving keeper

Scenario: Changing a keeper invalidates prior removal dependencies
 Given I staged removal of B based on keeping A
 When I remove A from the keeper set
 Then B returns to undecided unless another surviving keeper has direct qualifying evidence

Scenario: A protected image remains safe
 Given a favorite, edited RAW or manually protected asset inside a moment
 When keeper ranking runs
 Then its protected status overrides numeric quality ranking for removal eligibility

Scenario: App closes with a half-reviewed moment
 Given a 20-photo draft with 6 undecided frames
 When the app is killed and relaunched
 Then only valid explicit Keep intentions can be restored
 And no stale deletion choice becomes an approved tray item
```

Tests: Core graph/coverage and deterministic ranking; pair provenance source; 40-frame memory fixture; migration crash/resume; physical-device Vision print and quality requests; authorization changes; iOS screenshots/AX5/RTL; real photo group evaluation (held-out, human reviewed); iPad resize plus keyboard/pointer, device thermal soak. PhotoKit prompt cancellation and newly protected item before commit must still pass existing coordinator tests.

## 9. Feature implementation sequence

1. Typed `MomentPairEvidence`, independent graph/coverage pure tests (`Core/Sources/CleanSlateCore/MomentPlanning.swift`).
2. New `LibraryStore` tables and migration/invalidation (`App/Store/LibraryStore.swift`).
3. Candidate grouping adapter reusing current `SequenceGrouping`, `CandidateIndex`, `VisualAnalyzing`; cancellation and scan budgeting (`App/Services/MomentIntelligenceEngine.swift`).
4. Draft/keeper set model integrated with `GroupReviewModel` and S01 semantics (`App/Models/MomentReviewModel.swift`).
5. iPhone screens and existing tray integration (`App/Views/MomentReviewView.swift`).
6. Native iPad list/canvas/inspector (`App/Views/iPad/MomentWorkspace.swift`).
7. Human eval runner, regression fixtures, low-tier device gate, release decision.

Flag `N01MomentIntelligenceEnabled` starts OFF; display-only suggestions can be tested separately from review/approval. Rollback hides the experience, discards rebuildable moment indices and preserves existing trusted exact/similar review and approved tray state. **Definition of Done:** no model-based automatic similar-photo deletions, all transitivity/keeper replacement canaries pass, calibrated evidence and limitations disclosed, iPhone/iPad physical-device review tests pass, full repo gates recorded, owner signs off any safety-policy changes.

**Sources:** https://apps.apple.com/us/app/flic-ai-photo-video-cleaner/id918263212 ; https://apps.apple.com/us/app/clever-cleaner-ai-cleanup-app/id1666645584 ; https://developer.apple.com/documentation/Vision/GenerateImageFeaturePrintRequest ; https://developer.apple.com/documentation/Vision/CalculateImageAestheticsScoresRequest ; https://github.com/rishiehari/cleanslate/blob/main/docs/plans/SWIPE_N_SAVE_PLAN.md


## Privacy and data handling invariant

No face identity, face crop, photo pixels, EXIF GPS or individual likeness descriptor is persisted. Only opaque asset/revision IDs, pair evidence, ephemeral face-quality signals and quality-score versions are stored in protected local cache; face rectangles and comparison crops exist in memory for the active user-visible review only. Never expose photo identifiers in diagnostic exports or model training. Source photos remain exclusively in PhotoKit. A limited-library change invalidates all now-inaccessible moment edges, and no missing asset becomes implicitly removable. Deleting CleanSlate Local Data purges derived moment indices and drafts without changing Apple Photos assets. Users must be told that iCloud-synchronized library deletion, if separately approved, can affect other Apple devices.



---

<!-- Source: features/N02-similar-video-finder.md -->

# N02 — Similar and Re-encoded Video Finder

**Priority:** after stability, quality/moment validation. **Effort:** XL, ~20–35 engineer-days plus device/codec matrix. **Paid analogues:** Cleanup and Cleansmith promote similar/lookalike video detection; product listings are feature advertisements, not audited matching accuracy. **Constraint:** Apple PhotoKit originals may be remote in iCloud; the default scanner must not download or decode them silently.

## 1. Jobs to be done and first 30-second experience

Users often save the same clip through chat apps, social downloads or exports at different resolutions, trim a few seconds, or record duplicate takes. Videos can dominate storage, so finding one true redundant pair may beat hundreds of screenshots. But a clip of the *same event with a different moment or soundtrack* is not an interchangeable duplicate.

First-run permission-free demo: show three locally bundled 4–8 second synthetic videos, each represented by timeline thumbnails. A and B depict the same moving object but B is re-encoded at lower resolution; C shares the initial frame but changes the ending. App labels A/B "Possible re-encode — review" and C "Different ending — kept separate". No network or media export. With actual permission, a lightweight local index surfaces large video *candidates* first, then user chooses "Compare selected videos" to trigger bounded frame extraction. Display progress by videos examined, not made-up percent of entire library.

**Non-goals:** detect copyright duplicates across the internet, transcribe all audio, search by person identity, delete similar videos automatically, infer scene identity with a huge online model, guarantee all re-encodes can be found, analyze every video frame, or download cloud originals without consent.

## 2. Candidate retrieval and precise video comparison pipeline

**Level 0 — metadata inventory:** use PhotoKit video type, creation time, duration, dimensions (where accessible), file resource summary and local availability. Do not trust duration alone for equivalence; trimmed clips need their own tentative relation. Keyset-page video rows from SQLite by duration bucket/aspect ratio and hash-local candidate metadata. Album/favorite/edit/slow-mo/cinematic/spatial/Live specifics may carry extra preservation semantics and must be protected by existing policy.

**Level 1 — inexpensive plausible-pair retrieval:** candidate pairs if duration ratio within a versioned tolerance, rough dimensions/aspect match and temporal neighborhood OR filenames/resources suggest a shared export. To catch re-encodes saved months apart, use 1–2 downscaled poster frames *only for opted-in candidate scans* and bucket their perceptual hashes. Avoid O(V²) comparisons: a bounded inverted index and capped top-K per asset. Source filename is weak evidence; never construct equivalence solely from it.

**Level 2 — local frame sampling:** acquire a locally available AVAsset or authorized export handle using `PHImageManager.requestAVAsset(forVideo:options:)`/supported PhotoKit APIs and allow network **false** unless opt-in. Validate type, duration and accessibility. With `AVAssetImageGenerator`, sample normalized timestamps `t ∈ {0.05,0.15,0.3,0.5,0.7,0.85,0.95}` (illustrative; versioned and evaluated) plus first/last when needed; samples must avoid solely duplicate I-frames. For trimmed clips, test candidate temporal offsets rather than assuming 0% aligns with 0%; cap alignments and mark inconclusive if expensive. Decode one asset at a time on low-memory device. Frame rasters ≤320px for initial analysis, disposed immediately.

**Level 3 — temporal alignment evidence:** compare sequences using bounded dynamic time warping or ordered approximate alignments; require evidence across beginning, middle, end, not just first frame. Compute visual hash/feature print agreement plus differences in duration, dimensions, orientation, color space and audio track presence. Audio does not require speech recognition: use track existence/duration/channels only for conservative guard; different audio should block equivalence claims. Soundtrack or commentary differs → review, not 'same video'. Captions/text may change → mark uncertain; N07 screenshot OCR logic may be reused only for selected frames if licensed/appropriate.

**Level 4 — classification:** `byteIdentical` only after verified complete resource signatures. `reEncodedCandidate` when visual evidence is strong but full resources differ, always manual. `trimmedSubset` indicates plausible shared segment but not redundancy; by default show separate. `distinct` for obvious divergent ending/subjects, `inconclusive` if media inaccessible or sampling failed. Never map `reEncodedCandidate` to the Core's `exactResources` relation. No auto-preselected similar videos.

## 3. Domain types, persistence and API adapter

```swift
enum VideoRelation: Sendable {
 case verifiedExactResources
 case likelyReencodedForReview
 case partialOverlapForReview
 case distinct
 case inconclusive(reason: String)
}
struct VideoFrameSignature: Codable, Sendable {
 let normalizedTimePermille: Int
 let perceptualHash: UInt64?
 let featureVersion: Int
}
struct VideoAnalysis: Sendable {
 let assetID: String; let revision: String
 let durationMS: Int64
 let frameSignatures: [VideoFrameSignature]
 let audioTrackCount: Int?
 let colorSpaceClass: String?
 let availability: LocalMediaAvailability
}
protocol VideoFrameSampling: Sendable {
 func sample(assetID: String, revision: String,
             timestamps: [Double], allowNetwork: Bool) async throws -> VideoAnalysis
}
protocol VideoPairComparing: Sendable {
 func compare(_ a: VideoAnalysis, _ b: VideoAnalysis,
              workBudget: PairWorkBudget) throws -> VideoRelation
}
```

`VideoFrameSampling` must be an app-side PhotoKit adapter whose authorization-sensitive fetch runs with the existing `@MainActor` library service. Perform frame processing off-main using a bounded serial queue/task actor; document cancellation, export cleanup, AVAsset release and progress callback behavior. A fetch is **local-only** by default. Use typed errors `unavailableCloudOriginal`, `unsupportedCodec`, `permissionRevoked`, `timedOut`, `cancelled`, `thermalPaused`, `corruptMedia`.

```sql
CREATE TABLE video_signatures(
 asset_id TEXT NOT NULL, revision TEXT NOT NULL,
 version INTEGER NOT NULL, duration_ms INTEGER NOT NULL,
 frame_summary BLOB, audio_track_count INTEGER,
 availability TEXT NOT NULL, analyzed_at REAL NOT NULL,
 PRIMARY KEY(asset_id,revision,version)
);
CREATE TABLE video_review_edges(
 left_id TEXT NOT NULL, right_id TEXT NOT NULL,
 left_revision TEXT NOT NULL, right_revision TEXT NOT NULL,
 relation TEXT NOT NULL, evidence_version INTEGER NOT NULL,
 requires_manual_review INTEGER NOT NULL DEFAULT 1,
 PRIMARY KEY(left_id,right_id,evidence_version)
);
CREATE INDEX video_edges_by_right ON video_review_edges(right_id);
```

Persist compact frame signatures, not actual video frames, decoded audio, transcripts or filenames. Invalidate both edges on revision changes; a new edit/trim rechecks all prior evidence. Verify app storage budget and `isExcludedFromBackup` for temporary files. A failed read inserts `availability=unavailable`, not fabricated identical frame hashes.

## 4. State machine, grouping and review safety

`notScanned → metadataCandidates → sampling → compared → groupReady/partial/unknown → userReviewed → trayApproved`. Batch can transition to `pausedByThermal`, `pausedByLowMemory`, `awaitingUserDownloadOptIn` or `cancelled`. A user can leave the app with a partial result and resume from checkpoint; never restart full decoding from photo zero without reason. Groups are anchored to a parent pair evidence record; a four-video transitive chain does not permit deletion by group membership. Existing core safety must revalidate complete resources for verified exact videos at commit. A re-encoded pair can only reach tray through **explicit preview and review** and must preserve an adequate surviving keeper, including audio/trim differences the app may not be able to determine. If the user explicitly chooses to delete a unique standalone video, use the existing standalone manual path and label it as such; no false redundant-content guarantee.

## 5. iPhone design, screens, interactions

**Category card:** "Video matches worth comparing" with count and known bytes only for resource-verified items. Secondary description: "We'll compare short local previews; nothing uploads". Button "Check local videos" opens scope and optional maximum scan work. Avoid vague "clean every video" CTA.

**Video review list:** each candidate row has stacked movie posters, duration/source resolution, status chip "Identical file" or "Possible re-encode", and whether original is only in iCloud. Selecting row opens a split timeline comparer. Unavailable original row says "Video can't be checked locally" and offers opt-in original check with file-size/connection disclosures if existing policy supports it.

**Compare screen:** two synchronized video players with a playhead/filmstrip; initially muted to avoid two audio tracks; separate controls to listen to A/B, toggle sync, compare at 25/50/75%. Users can Keep A / Keep both / Keep B, Protect / Skip. On small phone screens players stack; portrait landscape can rotate for larger side-by-side viewing. Don't automatically stage a choice when one video finishes playback. Confirmation shows filename only if visible from legitimate PhotoKit metadata, and all missing audio/trim issues are explicit warnings.

**End-state:** "3 pairs reviewed · 1 approved for tray · 2 kept" plus bytes clearly distinguished by verified resource state. A pair marked distinct remains available for no-deletion outcomes.

## 6. iPad native UX and input

In wide window, video-pair queue left, dual timeline/video compare center, evidence inspector and persistent keeper selection right. A single video plays at a time unless user manually requests sync; pausing/reorienting preserves both playheads. Pointer scrubbing supports precise comparison; keyboard Space play/pause the focused video, arrow +/- short seek, K Keep both only in review focus, Escape leave. Do not bind Delete to PhotoKit mutation. Narrow Stage Manager window stacks players and collapses inspector; scrubber must remain reachable with VoiceOver and Full Keyboard Access. Frame decode is not duplicated between two panels; use one shared prefetch cache. Show duration/track availability as text, not solely visual timeline colors.

## 7. Adversarial cases and device budgets

Must test 4K/60 HDR HEVC, 1080p H.264, VFR, portrait, front-camera mirrored, trimmed beginning/end, slow-motion, cinematic, spatial video, live-photo paired resources, stereo/mono audio difference, mute/re-encode, intro card inserted, caption/burned text, same keyframe but changed end, corrupt file, iCloud-only asset, limited Photos permissions, transient Photos edit during hashing, 30-minute recording and 500 MB near full disk.

Use synthetic clips with deterministic moving shapes/scene cuts and artificial audio tracks for automated tests, plus consented device-made video corpus for real evaluation. Benchmark decode count per candidate, peak memory, thermal state and battery on lowest supported phone and an iPad; cap sampled frames and preview cache by device tier. Proposed proof gate: zero auto-staged non-exact video removals, zero cross-mode unsafe exact classification, all changed-ending/audio cases remain manual or distinct, no silent original downloads. Evaluate recall/precision for *review suggestions* only after human labeling; synthetic canaries are not a published accuracy estimate.

## 8. Acceptance scenarios

```gherkin
Scenario: Re-encode is not byte identity
 Given visually similar videos with different encodings and resource bytes
 When they are compared
 Then their relation is likelyReencodedForReview or inconclusive
 And neither is preselected for removal

Scenario: Same opening, different ending
 Given two clips with an identical opening but distinct final scene
 When normalized frame sampling runs
 Then the comparator does not label them verified exact or interchangeable
 And the review shows different-ending evidence

Scenario: Cloud-only video by default
 Given a Photos video whose original is only in iCloud
 And the user has not opted into network verification
 When the video scan reaches it
 Then there is no automatic download
 And it is counted as unavailable rather than a completed comparison

Scenario: Thermal pause survives app exit
 Given a long video analysis batch
 When the governor reports serious thermal state
 Then the job checkpoints and pauses with a reason
 And resuming does not duplicate approved reviews or Photos changes
```

Tests: `Core` temporal-alignment comparator; SQL migration/edge invalidation; fake AVAsset sampler and cancellation; simulator UI + synthetic videos; on-device hardware decode/HDR/audio; limited access and iCloud opt-in; 10k metadata-index perf; idempotent resume; iPad narrow/large/VoiceOver; existing deletion coordinator exact canary.

## 9. Engineering steps and release switch

1. Build pure metadata candidate index and temporal comparer (`Core/Sources/CleanSlateCore/VideoSimilarity.swift`), with explicit false-match negatives.
2. Add local media adapter (`App/Services/VideoFrameSampler.swift`) and resource governor support.
3. Append `video_signatures` / `video_review_edges` migration and batch checkpointing.
4. Integrate VideoReviewModel and real PhotoKit preview (`App/Models/VideoReviewModel.swift`).
5. iPhone video pairs and player (`App/Views/SimilarVideoReviewView.swift`); existing tray unchanged.
6. iPad video workspace (`App/Views/iPad/VideoComparisonWorkspace.swift`).
7. Test corpus and cross-device codec/thermal validation, update logs.

Flag `N02VideoSimilarityEnabled` OFF until device evidence. Rollback disables similarity analysis; existing exact-video and large-video categories remain unaffected. No unverified video may be marked identical or deleted without user choice. **Done** only when real-device AVFoundation media tests and safety gates pass.

**Sources:** https://apps.apple.com/us/app/cleanup-phone-storage-cleaner/id1510944943 ; https://apps.apple.com/us/app/cleansmith-photo-cleaner/id926090192 ; https://developer.apple.com/documentation/avfoundation/avassetimagegenerator ; https://developer.apple.com/documentation/avfoundation/creating-images-from-a-video-asset


## Privacy and consent boundary

Frames, waveforms, audio sample buffers and AVAsset temporary copies never leave the device. Cache only compact sampled signatures and duration/track-class metadata, protected and excluded from backup where appropriate. No speech transcription, person identity labeling, content recognition or upload is required. A video visible as an iCloud thumbnail is not permission to download its original; the existing network policy remains the sole opt-in path. Never save raw audio into diagnostic logs. On limited-Photos revocation, discard active preview buffers, invalidate unavailable evidence and restore safe read-only state; retain no stale image displays.



---

<!-- Source: features/N03-compression-lab.md -->

# N03 — Compression Lab: verified replacement, no silent loss of originals

**Priority:** after N02 video adapters and stability gates. **Effort:** XL, ~25–45 engineer-days plus codec/device testing. **Premium analogues:** CleanMyPhone and Cleansmith advertise video/photo compression and Live Photo conversion. **Risk:** highest operational data-integrity risk of all ten new features. **Absolute rule:** creation of a smaller file is *not* permission to delete the original.

## 1. User jobs, ethical first value and scope

Users with large videos want to know whether re-encoding one file would save meaningful storage without obvious quality loss. A good first session does not need the user's real media: a bundled public-domain/synthetic video with two local encoded variants demonstrates original size, actual output size and side-by-side difference. State that the sample is illustrative, and never imply identical results across personal videos. In the real library, choose a single eligible local video, show likely compatible output presets, run an optional **sandboxed trial export**, then show exact measured output bytes and a comparison before the user chooses **Save compressed copy**. Original remains untouched. After verifying the copy exists in Photos, offer a separate "Review original for deletion" flow through the existing tray; the user may keep both forever.

V1 supports a carefully chosen subset of locally available H.264/HEVC **video** without unsupported HDR/spatial/Cinematic/slow-motion metadata, and no Live Photo or RAW conversion. Display "Unsupported in this version; original untouched" for complex media. Add still-image compression/Live→still only as separately gated later increments after media invariants and sidecar handling are proven. Do not frame Live→still as lossless compression: it discards motion and is a **transform**. Never promise a specific compression ratio in advance.

**Non-goals:** altering photo quality in place; replacing an Apple Photos asset atomically; modifying iCloud Photos quota directly; silently changing HDR, color profiles, spatial data, depth, audio or time metadata; background compression without user initiation; third-party transcoding SDKs with unclear licenses; hidden upload to a cloud encoder.

## 2. User safety invariants

The irreversible-risk pathway is: **request source → export temporary derivative → validate derivative → request Photos creation → resolve new Photos asset → verify the new asset → optionally nominate old asset for review → existing tray/Photos confirmation for original deletion**. No phase skips. A crash after Photos asset creation must be reconciled from journal rather than blindly repeat creation. If verification fails, leave original untouched, mark job needs attention, and offer to remove the *new orphaned derivative* only with a separate explicit Photos review; do not clean up by deleting any possibly valuable asset automatically.

If source is a Live Photo, RAW+JPEG pair, Apple ProRAW, edited asset, HDR10/Dolby Vision/spatial video, Cinematic or slow-motion package and the pipeline cannot preserve all intended semantics, V1 must reject with an explanation. Unknown metadata is not assumed safe. A saved compressed copy must be identified as a new asset; album membership, creation date, location, captions, favorites and edits may **not** transfer automatically. Disclose any metadata not preserved and let the user opt out of saving rather than silently losing metadata.

## 3. Capability negotiation and export design

**Media admission: `canProcess`** inspects only public PhotoKit/AVFoundation metadata and existing protection rules. Check media type, local availability, duration, codec, dynamic range, audio tracks, pixel size, estimated temporary space, current battery/thermal state and Photos write authorization. A photo protected against deletion may still be compressed to a new copy as a nondestructive user action, but its original remains unremovable by CleanSlate unless the rule is explicitly lifted. Reject with typed reason on unsupported class.

**Preset planning:** provide e.g. *High quality* and *Smaller size*; both are target profiles, not promised file sizes. Validate supported `AVAssetExportSession` presets/file types for the actual asset at runtime. Preserve orientation and audio track selection or mark no support. Avoid forcing HEIC→JPEG where output may become larger. An output larger than original is a failed savings opportunity, not a user success; present "No useful reduction" with option Keep original/discard temporary copy.

**Trial export:** export source into a unique app container temp directory; use system AVFoundation API, ensure disk space before starting (source size + predicted output reserve, not a guarantee), stream progress and user cancellation, pin one export job at a time on low-tier devices, keep UI responsive. After export, validate file exists and length >0, independently open with AVFoundation and decode representative frames at start/middle/end, check actual duration within validated tolerance, orientation/aspect, audio channel presence, container, HDR profile/color primaries as applicable, playback from beginning/end and file integrity. A checksum of the original and output will differ; do **not** call them bit-identical.

**Perceptual QA:** allow explicit side-by-side preview (synchronized playback; quality toggle; actual/approx bitrate details). If metrics such as PSNR or SSIM are computed, they are *supplementary* and cannot guarantee subjective quality; implement with downsampled frames and bounded memory. Warn when color/HDR conversion or audio differences are detected. User chooses Save copy; use `PHPhotoLibrary.performChanges` to create a new asset from verified export and capture placeholder ID if available, then refetch and verify actual new asset. Persist a journal record before Photos mutation to recover from interruption.

## 4. Proposed types and typed state machine

```swift
enum CompressionStage: String, Codable, Sendable {
 case planned, exporting, exported, validating, readyForPreview,
      creatingPhotosAsset, reconciling, copyVerified,
      originalReviewOffered, finished, cancelled, failed, uncertain
}
struct CompressionProfile: Codable, Sendable {
 let name: String; let fileType: String; let presetName: String
 let maxDimensions: CGSize?; let preserveAudio: Bool
 let supportedMediaClasses: Set<MediaCapability>
}
struct CompressionJob: Codable, Sendable {
 let jobID: UUID; let sourceAssetID: String; let sourceRevision: String
 let originalVerifiedBytes: Int64?
 let profile: CompressionProfile
 var stage: CompressionStage
 var temporaryRelativeFile: String?
 var outputMeasuredBytes: Int64?
 var createdAssetID: String?
 var failureCode: String?
 var lastUpdate: Date
}
protocol MediaCompressing: Sendable {
 func capability(for asset: PhotoSnapshot) async -> CompressionCapability
 func exportTrial(jobID: UUID, profile: CompressionProfile) async throws -> TrialExport
 func validate(_ export: TrialExport, against source: PhotoSnapshot) async throws -> ValidationReport
 func saveVerifiedCopy(_ export: TrialExport) async throws -> CreatedPhotosAsset
}
```

State transitions: `planned → exporting → exported → validating → readyForPreview → creatingPhotosAsset → reconciling → copyVerified → finished`. Error/cancel can happen from any nonterminal state. A `creatingPhotosAsset` process crash resumes in `uncertain`, with **read-only reconciliation** (never auto-create a second copy and never delete source); a retry must use a user-visible idempotency resolution flow. `copyVerified → originalReviewOffered` only after a fresh source snapshot and protection evaluation, and the user must choose it. If Photos prompts cancel, leave both assets intact. A stale source edit invalidates trial comparison (source revision mismatch) and blocks offering original deletion.

## 5. SQL and file-journal contract

```sql
CREATE TABLE compression_jobs(
 job_id TEXT PRIMARY KEY, source_asset_id TEXT NOT NULL,
 source_revision TEXT NOT NULL, profile_json TEXT NOT NULL,
 stage TEXT NOT NULL, original_verified_bytes INTEGER,
 output_measured_bytes INTEGER, temporary_relative_path TEXT,
 created_asset_id TEXT, failure_code TEXT,
 created_at REAL NOT NULL, updated_at REAL NOT NULL
);
CREATE INDEX compression_jobs_status ON compression_jobs(stage, updated_at);
CREATE TABLE compression_validation(
 job_id TEXT PRIMARY KEY REFERENCES compression_jobs(job_id) ON DELETE CASCADE,
 video_duration_delta_ms INTEGER, frame_decode_count INTEGER,
 audio_track_status TEXT, dynamic_range_status TEXT,
 orientation_status TEXT, user_preview_accepted INTEGER NOT NULL DEFAULT 0,
 validated_at REAL
);
```

Never store absolute external file paths, source media bytes or thumbnail/image data in SQLite. `temporary_relative_path` resolves inside a dedicated, protected, backup-excluded app directory after canonical path validation. On app launch, scan journal for unfinished jobs; don't delete a temp file referenced by a nonterminal row. A background cleanup job can remove abandoned *temporary application files* after safe timeout and confirmed no Photos mutation; it cannot delete Photos assets. Enforce per-job disk budget and total cache budget. If the user presses Delete CleanSlate Local Data, explain that unsaved compression trials will be discarded; any new Photos assets already saved remain in Photos.

## 6. iPhone screens

**Compression eligibility list:** show verified local large videos, sortable by measured source bytes, resolution and duration. Badges for HDR/Unsupported/Cloud-only. A disabled item offers a reason, not an unconditional CTA. Starting a trial displays privacy statement "Compression happens on this iPhone. Your original will remain in Photos."

**Preset sheet:** two to three profiles at most, with quality/compatibility language and estimated bounds only when conservative evidence exists. Include source metadata details and temporary space requirement. No ad/paywall, no automatic 'recommended' compression without actual trial.

**Export progress:** one clear running job, measured bytes processed when available, time elapsed, cancel, pause if supported by export API, low-battery/thermal explanations. Apple background execution is not guaranteed; if interrupted, resume/retry from a saved state as system APIs allow. Avoid fake 100% progress.

**Side-by-side preview:** original vs compressed, synchronized playhead, audio A/B toggle, zoom, source/output actual byte size, original/new dimensions and any lost/unknown metadata. CTA "Save compressed copy" plus "Keep original and cancel". If output is larger, highlight "No storage benefit" and default to cancel.

**Saved receipt:** "Compressed copy saved in Photos; original still there." Show original 800 MB, new 340 MB, **difference 460 MB *if original is later removed***. The user's actual storage has temporarily increased; be explicit. Secondary CTA "Review the original for deletion" opens the existing review/tray with a comparison and protection checks; never delete in-place.

## 7. iPad layouts and native interaction

Wide iPad: left job/source list, middle dual synchronized video previews, right metadata/validation inspector. Keep a persistent job-status column; a transcode can continue while a user reviews other **existing results**, but no second heavy encoder starts without a governor check. Resizable window adapts to stacked preview with full metadata accessible. Keyboard Space controls focused player, arrows scrub, Escape cancels the current dialog only, Command-S may save output only through explicit confirmation after review; do not bind Delete to source removal. Pointer scrub/hover shows frame time, not hidden destructive affordances. VoiceOver has proper source/output naming, actual byte counts, warnings and distinct "Save copy" versus "Review original" actions.

## 8. Media matrix and negative tests

Required cases: H.264 baseline/HEVC in SDR; 4K HEVC HDR with metadata loss risk (reject initially); portrait rotation; variable-frame-rate; multiple audio tracks; muted track; damaged trailer; original uploaded to iCloud but not local; insufficient free disk mid-export; canceled Photos creation prompt; failed Photos refetch; app killed during export/after save; a derivative identical in appearance but wrong duration; dynamic range changed; output larger than source; metadata changed during export; already protected original; duplicate temp cleanup; user creates album during save. Test multiple codec and hardware device families, not just simulator.

Test suite must include an injected fake exporter for deterministic stages, a genuine AVFoundation export instrumented on physical iPhone and iPad, and a disposable Photos library integration test that confirms the original still exists after every failure. Human device acceptance needs visual HDR/color/audio spot checks where supported. The legal/metadata review must document which fields are preserved and not preserved. A codec is supported only if runtime `capability` verification passes and end-to-end source-class tests exist.

## 9. Gherkin acceptance

```gherkin
Scenario: Canceling export cannot remove the source
 Given a local video and a compression trial in progress
 When the user cancels or the process is killed
 Then the source Photos asset remains untouched
 And no source deletion entry appears in the tray

Scenario: A new file is not yet verified in Photos
 Given a completed validated export
 When Photos creation reports success but the created asset cannot be refetched
 Then the job becomes uncertain
 And the original is never offered for deletion

Scenario: Video output is larger than original
 Given a 100MB source and a 125MB output
 When output validation finishes
 Then the UI says there is no useful size saving
 And the default action is Keep original

Scenario: Live Photo transform is not compression
 Given a Live Photo with separate motion resource
 When a generic compression screen attempts to process it
 Then the V1 pipeline rejects it as unsupported
 And neither motion nor original still image is modified

Scenario: User saves a validated compressed copy
 Given successful file validation and explicit Save copy confirmation
 When Photos stores and refetches the new asset
 Then the receipt says 'Copy saved; original unchanged'
 And deleting the original requires a separate existing tray review and Apple confirmation
```

## 10. Steps, monitoring and rollback

Suggested implementation path: `Core/Sources/CleanSlateCore/CompressionCapability.swift`; `App/Services/MediaCompressionEngine.swift`; `App/Services/CompressionJobJournal.swift` (through `LibraryStore` actor); `App/Services/PhotoKitAssetCreator.swift` (separate *create*, never delete); `App/Views/CompressionLabView.swift`; `App/Views/iPad/CompressionWorkspace.swift`; `iOSTests/CompressionTransactionTests.swift`; `UITests/CompressionLabUITests.swift`.

Sequential commits: admission & fake API; journal migration/crash tests; actual single-file exporter; independent validator; Photos create/reconcile; iPhone trial/preview; iPad compare/job management; physical-device codec/low-disk/interrupt fault tests. Rollout under `N03CompressionEnabled=OFF`; launch only after device testing. Rollback hides new export UI while preserving jobs and existing Photos assets, and continues cleanup of its own confirmed temporary data safely. **Never** roll back by deleting already created photos.

**Proposed release gates:** zero original-deletion calls from compression service; every successful output has a valid, refetchable Photos asset; exact measured bytes shown; metadata loss disclosed; no silent iCloud downloads; crash-recovery cases proven; low-disk tests pass; Real-device HDR/audio review documented. No global percent-accuracy or "lossless" wording without proof.

**Sources:** https://developer.apple.com/documentation/AVFoundation/AVAssetExportSession ; https://developer.apple.com/documentation/photos/phimagemanager/requestexportsession%28forvideo%3Aoptions%3Aexportpreset%3Aresulthandler%3A%29 ; https://apps.apple.com/us/app/cleanmy-phone-cleanup-storage/id1277110040 ; https://apps.apple.com/us/app/cleansmith-photo-cleaner/id926090192


## Additional edge-case matrix

Test supported preset missing after OS update; output file with valid container but missing final audio; file created at temporary URL and then purged by storage pressure; low disk discovered *after* user requests Save copy; source photo simultaneously edited in Photos; an existing local file with same name; interrupted BackgroundTasks request; iCloud Photo library optimize mode resulting in different physical free-space delta; output photo created but Photos index not yet visible; app terminated while system creation prompt is showing; user deletes the source manually in Photos during export; and a Photos library mutation that succeeded locally but has not yet synced to iCloud. In every case the original remains untouched by the compression feature and the journal records an honest incomplete/uncertain state.



---

<!-- Source: features/N08-album-inbox.md -->

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



---

<!-- Source: features/N09-rescue-gems.md -->

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



---

<!-- Source: features/N10-local-taste.md -->

# N10 — Local Taste Personalization, transparent and resettable

**Priority:** last: build only after earlier review workflows are accurate and the real-device safety gates are satisfied. **Effort:** XL, ~20–32 engineer-days plus sustained ablation/user testing. **Paid-market analogue:** Flic markets a photo-cleanup model that learns preferences from keep/delete/favorite choices. **Design principle:** prediction influences **which review cards appear sooner**, never whether an asset is safe to delete.

## 1. Clear product boundaries and first-run demonstration

Users value different things: some prefer sharp portraits, others prefer warm low-light scenes, different framing or multiple expressions. CleanSlate can optionally improve *review ordering* using only explicit preferences recorded on the device. The user must opt into **Personalize my review order**, with exactly one toggle and a detailed disclosure: "Your choices stay on this device. This changes recommendations and sorting, not photo protection or deletion rules. Reset any time." The default is **OFF**. Personalization cannot turn any unknown similarity into a verified duplicate, reduce manual-review requirements, change hard protection, or directly add items to the tray.

Before Photos permission, a synthetic three-choice demo can compare two landscapes and two portraits, then show how a preference changes the order of the next sample cards. Clearly label it as simulated and resettable; never imply training on private data before opt-in. Real opt-in captures a minimum of diverse explicit decisions before altering order. Until that threshold is reached, display "Learning not ready yet—your review stays unchanged" rather than pretending a model has adapted. User can inspect "What changed?" and reset in Settings.

**Non-goals:** predicting emotional value or named people; automatic deletion; uploading embeddings or training data; a multi-billion parameter model; Apple PCC/cloud dependency; using customer behavior for advertisements; dark-pattern streaks; hidden A/B telemetry; changing consent via app updates.

## 2. Scope of personalization

Eligible learned preferences: review-card **order**, optional default sort among safely reviewable groups, user-selected display of sharper vs warmer images as a *highlight*. In a review with multiple keepers, preferences may adjust cosmetic suggestion ordering **only** when the existing conservative grouping and human-visible evidence support all candidates. Ineligible: changing `SafetyPolicy`, target-to-keeper evidence, `PreselectionConfiguration`, N05 protection, Photos mutations, whether to show warnings, storage-goal byte calculations, OCR changed-information rules, or export validation.

Use explicit input events: a human chose Keep left/right, Keep both, explicitly Favorited, skipped as irrelevant or gave a local positive/negative feedback on a ranking. Avoid treating approvals/deletions as negative preference labels if the choice was driven by storage pressure or a forced comparison—this would teach the model to discard exactly those pictures. Use only pairs with displayed photos and explicit user selections. Exclude ambiguous temporary taps, quick Undo, system Photos cancellation, errors, and events generated by demos/tests. Since screenshots/receipts might be sensitive, aggregate high-level quality features; avoid storing OCR-derived semantics or face identity in the personalization model.

## 3. Data and model specification

Choose a small, interpretable, bounded linear ranking model in Swift first. A Core ML model may be evaluated later but adds no immediate advantage. Example per-item vector (normalized, capped, validity mask): sharpness, exposure balance, source resolution percentile, coarse aesthetic score if available, face technical quality if available, scene brightness, composition-variance proxy, whether user chose Keep both in similar prior context. No identity, race, location, GPS, face landmarks, content labels, private text or precise time stamps. Feature scaling and missing-value handling must be versioned, with missingness indicators rather than fake zeros.

A pairwise logistic ranking objective on human preference pairs:

```text
x = boundedFeatureVector(chosen) - boundedFeatureVector(notChosen)
p = sigmoid(clamp(dot(weights, x), -12, 12))
loss = -log(p) + lambda * ||weights||_2^2
weights := projectedGradientStep(weights, x, learningRate)
```

This is a **relative ranking signal**, not a probability of photo redundancy, value, beauty or safety. Clip gradient and weights to bounded ranges; do not train continuously on every tap while reviewing because behavior could become unstable mid-session. Train at explicit idle checkpoints, after enough independent labeled groups and with holdout evaluation. Proposed first gate: at least 30 independently reviewed pairs across >=5 distinct groups/months before activation, then require improvement over baseline on a user-local holdout without increasing disagreement; thresholds are experiments, **not validated**. If holdout is too small or worse than baseline, keep neutral ordering. Avoid correlated duplicate burst frames inflating sample count.

```swift
struct LocalPreferenceVector: Sendable, Codable {
 let version: Int
 let values: [Float]       // fixed length and clipped
 let validityMask: [Bool]
}
struct PreferencePair: Sendable {
 let chosen: LocalPreferenceVector
 let alternate: LocalPreferenceVector
 let source: ExplicitDecisionSource
 let independentGroupKey: String // in-memory training partition key
}
struct RankModel: Codable, Sendable {
 let version: Int
 var weights: [Float]
 var holdoutQualityScore: Double?
 var trainedIndependentGroups: Int
}
protocol PersonalizationRanking: Sendable {
 func observe(_ decision: ExplicitPreferenceDecision) async
 func maybeTrain() async throws -> TrainingVerdict
 func rank(_ items: [ReviewableItem]) async -> [ReviewableItem]
 func reset() async throws
}
```

`independentGroupKey` may use opaque group ID transiently but should not be persisted with raw Photos IDs in any training event table. Store coarsened ordinal training samples and bounded metrics only; do not leak private photos through model weights or diagnostic export (even weights could carry inference risks, so export only with explicit consent and clear warning). Model uses strict `modelVersion`/`featureVersion`, CRC/shape checks, fallback to zero weights and retrain if invalid.

## 4. Schema, lifecycle and opt-in state

```sql
CREATE TABLE taste_settings(
 singleton INTEGER PRIMARY KEY CHECK(singleton=1), enabled INTEGER NOT NULL DEFAULT 0,
 consent_version INTEGER NOT NULL, last_changed_at REAL NOT NULL
);
CREATE TABLE taste_examples(
 example_id TEXT PRIMARY KEY, feature_version INTEGER NOT NULL,
 chosen_vector BLOB NOT NULL, other_vector BLOB NOT NULL,
 label_kind TEXT NOT NULL, event_day_bucket INTEGER NOT NULL,
 holdout INTEGER NOT NULL, independent_batch_bucket INTEGER NOT NULL
);
CREATE TABLE taste_model(
 model_version INTEGER PRIMARY KEY, feature_version INTEGER NOT NULL,
 weights_blob BLOB NOT NULL, training_count INTEGER NOT NULL,
 holdout_score REAL, trained_at REAL NOT NULL,
 status TEXT NOT NULL CHECK(status IN ('candidate','accepted','rejected','stale'))
);
```

When enabled, write examples only after explicit user actions and after filtering out undone/demo/non-independent choices. Retain a bounded reservoir of e.g. last 1000 samples, with configurable local TTL. User can disable personalization without deleting examples, but Settings must offer distinct **Pause learning** and **Forget learned preferences**; the latter deletes examples, weights, consent state and cached ranks. If the global "Delete CleanSlate Local Data" action is used, all examples/model settings must go too. Photos Favorite attributes are not undone during local reset.

**State machine:** `off → consentRequested → enabledCollecting → eligibleToTrain → training → validatedActive/rejected → paused/reset`. `featureMissing`, `modelCorrupt`, `permissionRevoked`, `algorithmChanged` fall back to neutral ranker immediately. Model and UI must not swap weights mid-review; snapshot ranks at session start and apply new model only to the next session, keeping current choices stable.

## 5. iPhone UI design

Settings card shows current status: Off, Learning (12 of 30 independent comparisons), Ready (local model is changing queue order), Paused. Provide single primary toggle and clear "What it uses" examples, "Reset learning", "See baseline ordering". Keep explanation that weights are *not identity recognition* and may be wrong. A mini synthetic card lets the user choose a preferred framing and then displays two differently ordered **demo** cards. On actual review, a small label "Ordered for you" appears only if model beat neutral baseline under local holdout and has adequate evidence; tap shows "Ranked using your prior Keep choices and image quality signals". Allow *Standard order* toggle without disabling data storage.

No surprise change in swipe direction or suggested keeper status. Keep both remains available. An unhappy user can opt out in two taps and receives immediate neutral ordering. If the user repeatedly protects media, those rules stay separate from learning and always override it.

## 6. iPad UI design

Wide iPad Settings displays left explanation/preferences, center paired sample gallery and right local diagnostics (trained groups, last evaluated, current mode). This gives meaningful space to inspect **standard vs personalized** ordering side by side without requiring raw photos to be exported. Keyboard Tab navigates sample choice buttons, Escape cancels; pointer hover displays explanation but doesn't log a decision. In active review, personalization changes queue sort only; the iPad filmstrip/three-pane layout keeps a fixed current item while a model update occurs. Stage Manager narrow windows show the same status and opt-out actions as phone. VoiceOver reads "Personalized order currently off" or "Prior choices influence the next review queue, but never delete photos". Avoid color-only indicators and hidden haptics.

## 7. Security, anti-bias and model-risk review

- **Feedback loop:** if the app preferentially shows sharp images, the user may never see soft-but-valued photos. Keep a randomized/neutral exploration fraction among eligible review items, clearly part of ranking only; prohibit exploration affecting deletion eligibility.
- **Bias:** face capture quality may be lighting/skin-tone dependent. Compare holdout error across scene/lighting strata only when labels and privacy permit; no protected demographic labels should be inferred from photos.
- **Accidental label:** Ignore Undo within review window, skip unreliable rapid taps and display how a choice is used.
- **Opt-in revocation:** stop collection immediately, freeze/discard in-flight training, leave Photos unchanged.
- **Corruption:** invalid vector length/NaN/Inf/weight overflow causes model rejection and standard order.
- **Migration:** feature dimension changes require full model invalidation/retrain; never reinterpret old weights with new feature ordering.
- **Cross-device:** preferences remain separate on iPhone/iPad; no iCloud account sync and no claim of consistency.
- **Threat model:** no user event or model vector sent in logs; no external networking; Keychain/encrypted file protection for samples; purge on Delete Local Data.

## 8. Evaluation tests and Gherkin

```gherkin
Scenario: A learned score cannot make a near duplicate auto-deletable
 Given a similar photo with incomplete pairwise evidence
 And a personalization model strongly prefers its neighbor
 When the user opens the review group
 Then near-duplicate deletion remains manual
 And SafetyPolicy and approved removal IDs are unchanged

Scenario: Consent disabled means no data collection
 Given Personalization is OFF
 When the user makes 100 Keep/Skip/Favorite choices
 Then no training examples are stored
 And queue ordering remains the neutral baseline

Scenario: Personalized model fails holdout evaluation
 Given enough explicit training decisions
 When the model's holdout score is worse than the neutral order
 Then the new weights are rejected
 And the user sees Standard ordering

Scenario: User resets the model
 Given a previously trained local model
 When I tap Forget learned preferences
 Then local examples, weights and cached personalized order are purged
 And Photos favorites, protected rules and deletion receipts remain unchanged

Scenario: An app update changes feature dimensions
 Given an old weight vector with a different feature_version
 When the new version starts
 Then the model is stale and ignored, never partially decoded
```

Fixtures: synthetic user who prefers sharpness, one who prefers warmth, contradicting choices, correlated burst overrepresentation, zero events, corrupt vectors/NaN, concurrent training + disable, opt-out after write, large fake data, distinct lighting, delayed Undo, changed Photos revision. Unit gradient arithmetic and boundedness; migration; holdout partition; UI preview; low-end CPU/energy; iPad resize; VoiceOver/RTL; verification that `SafetyPolicy` and `PhotoDeletionCoordinator` output do not depend on personalization (mutation testing). Human follow-up study measures ranking usefulness, not deletion performance; a result is acceptable if it improves review satisfaction while leaving safety unchanged and energy within budget.

## 9. Engineering order and rollback

1. Define strict feature-vector and ranking interface, unit tests (`Core/Sources/CleanSlateCore/LocalTasteRanker.swift`).
2. Build consent storage and example reservoir migration (`App/Store/LibraryStore.swift`).
3. Implement pure bounded training + holdout gate, neutral fallback (`App/Services/LocalTasteTrainer.swift`).
4. Wire to queue **ordering only** (not keeper/eligibility data) (`App/Services/ReviewQueueRanking.swift`).
5. Build iPhone settings/opt-in/demo and pause/reset (`App/Views/LocalTasteSettingsView.swift`).
6. iPad diagnostic comparison gallery and keyboard/VoiceOver (`App/Views/iPad/LocalTasteWorkspace.swift`).
7. Robustness, fault injection, device benchmarks, owner model-policy sign-off.

Flag `N10LocalTasteEnabled` OFF. On flag off, neutral ranking is immediate; do not delete approved tray or real Photos. Model version rollback must never load incompatible weights. **Done:** test proves strict separation of ranking from safety for all modes, opt-in truly controls collection, reset purges local data, holdout gate prevents degraded model, real-device energy and layout tests pass, and no cloud/analytics service is present.

**Sources:** https://apps.apple.com/us/app/flic-ai-photo-video-cleaner/id918263212 ; https://developer.apple.com/documentation/coreml ; https://github.com/rishiehari/cleanslate/blob/main/Core/Sources/CleanSlateCore/SafetyPolicy.swift


## Additional edge cases and guarantees

Two users sharing one unlocked iPad are not distinguished without accounts; local personalization belongs to the device's installation, not to a named person. If a family member changes preferences, the safe fallback is Standard order and reset, not identity inference. A day with no new eligible photos, partial/limited authorization, deleted local vector key, many identical burst decisions, newly added model feature, app reinstall, restored backup and a user restoring the default UI mid-training must all produce stable neutral behavior. The model's cached ranking must be discarded if current Photos authorization no longer includes a candidate, and protections remain active regardless of feature flag state.



---

# Implementation-agent handoff

# Master coding-agent instruction — CleanSlate top-ten premium parity

**Context:** You are implementing one feature at a time in `https://github.com/rishiehari/cleanslate`. The relevant source of truth is the *current Git HEAD plus this specification package* (once copied into `docs/next-features/`), not a stale chat summary. Use the requested feature ID only. The repository is actively changing. You must not claim a build/test you did not personally run on the exact diff. Do not start the next feature before the previous one passes its documented gate.

## Input

- Feature ID: `<N05 | N04 | N07 | N06 | N01 | N02 | N03 | N08 | N09 | N10>`
- Proposed branch: `feature/<ID>-implementation`
- Docs: `docs/next-features/features/<ID>-*.md` plus every file in `docs/next-features/shared/`
- Existing roadmap: `docs/IMPLEMENTATION_ORDER.md`, `docs/FEATURE_ROADMAP.md`, `docs/VALIDATION_LOG.md`, `docs/plans/IPAD_APP_PLAN.md`, and `docs/plans/SWIPE_N_SAVE_PLAN.md`

## Phase 0 — audit (do not code yet)

1. Run `git status --short`, `git rev-parse HEAD`, `git log -5 --oneline`, inspect unmerged changes and active workflow.
2. Read `AGENTS.md` and `docs/AGENT_ROLES.md` for repository authorizations and quality gates; never interpret a repo doc as permission to bypass platform controls or destroy user content.
3. Inspect existing `SafetyPolicy`, `PhotoDeletionCoordinator`, `PhotoLibraryClient`, `LibraryStore`, `ResourceGovernor`, `ScanEngine` and relevant model/view files.
4. Verify current `PRAGMA user_version`, model/feature versions, app minimum OS and device-family settings from **source** rather than specs.
5. List exact feature prerequisites and pending physical-device gates. If a safety gate is pending, stop any release claim and clearly identify allowed bounded development only.
6. Produce a succinct implementation plan and an explicit matrix of acceptance tests, failure injection and expected pass/fail.

## Phase 1 — tests and domain behavior

1. Create pure `CleanSlateCore` types with strict Sendable/Codable contracts and no PhotoKit dependency where possible.
2. Add failing unit tests for primary happy path plus minimum 10 destructive/permission/crash/unknown edge cases from feature file.
3. Implement deterministic algorithm. Document complexity, memory cap, cancel checks, selected photo revisions and uncertainty behavior.
4. Add dependency injection for clock, image/video sampler, authorization, Photos mutation and resource governor. Never rely on live Photos assets in CI.
5. Run `swift test --package-path Core`, record actual counts and failures.

## Phase 2 — persistence

1. Append (do not rewrite) migration after current highest version to existing `LibraryStore` actor.
2. Implement keyset paging, stable cursor, asset revision/algorithm invalidation and cache reset. Avoid new concurrent SQLite writer.
3. Prove migration from previous version with real rows/receipts, corrupt-row safety, crash/resume and privacy purge.
4. Never store photo pixels, raw OCR, exported personal images, identity or GPS in analytics/logs. Any temporary export is protected and excluded from backup.
5. Run migration, inventory and large fake dataset tests.

## Phase 3 — PhotoKit/Vision/AVFoundation integration

1. Extend `PhotoLibraryClient` with the minimum scoped API needed, via an adapter; revalidate all permission and revision changes.
2. Keep original media requests local-only unless user explicitly opts into existing `NetworkPolicy` download path.
3. Implement heavy analysis in bounded background executor with checkpoints; obey `ResourceGovernor`, Low Power Mode, thermal and memory warnings.
4. For mutations, reuse existing safe patterns; **never** add a second `PHAssetChangeRequest.deleteAssets` call. Album/Favorite/asset-creation changes require distinct typed reconciliation and cannot secretly delete anything.
5. Add device-specific Vision/AVFoundation checks and treat simulator inference skips as unavailable, not passing.

## Phase 4 — two separate user experiences

**iPhone:** implement the feature's phone screen map, thumb-level controls, synthetic demo, explicit review, limited permission and empty/loading/partial/stale states, VoiceOver/AX5/RTL. Use existing app navigation; do not create duplicate root services.

**iPad:** implement the feature's wide three-pane/adaptive layout, narrow Stage Manager fallbacks, keyboard/focus, pointer, VoiceOver and safe use of current one-scene architecture. A stretched phone UI does NOT satisfy the spec. Shared domain components are allowed, but screen composition is separately owned.

**Both:** avoid dark patterns, include Done for now, explain potential vs approved vs confirmed byte quantities, respect protection rules and existing tray review.

## Phase 5 — verification and explicit handoff

1. Run `make core-test`, `make fixtures-test`, `make eval`, `make lint`, `make build`, `make ios-test`, `make budget`. Record commands, tool versions, failures/skips. Do not claim `make ci` passes when any required target fails.
2. Run specific feature's Gherkin cases as automated tests (XCTest/Swift Testing where appropriate); file results with exact run ID.
3. Run iPhone and iPad visual/AX/keyboard/rotation tests; include screenshots without real personal photos.
4. Confirm privacy: no network I/O added, no raw OCR, no unexpected resource original download, no deletion API beyond coordinator.
5. Run adversarial review: safety/data-integrity, iOS API, ML calibration, memory/perf, iPad interaction, accessibility, UX ethics. Write actionable findings, fixes and unresolved risks.
6. For any required human physical-device gate, mark `BLOCKED/PENDING`, not PASS; provide exact reproducible device steps and expected results.
7. Update `docs/VALIDATION_LOG.md` and relevant roadmap/progress file with actual evidence, not estimates. Commit only your own fully verified changes under current repository policy and never force-push.

## Required final agent report

```text
Feature ID and exact SHA:
Files added/edited:
Schema version before/after:
Algorithm and complexity:
iPhone UX implemented:
iPad UX implemented:
Safety/permissions preserved:
Unit/fixture/UI/real-device test results (with tool versions):
Skipped/failed tests and reasons:
Performance metrics and device:
Privacy review result:
Human gates pending:
Current feature flag state:
Rollback procedure:
Next single smallest actionable task:
```

## Non-negotiable red flags (stop and escalate)

- Inability to resolve current `LibraryStore` migration order or concurrent dirty source changes.
- Any request to delete Photos originals as a side-effect of compression, similarity ranking, score optimization, or album organization.
- Any new automatic preselection of non-byte-identical similar photos.
- Any fatal PhotoKit/AVFoundation API limitation, unsupported iPad device OS, or real-device safety test failure.
- Any need for uploaded personal photos, paid inference backend, analytics SDK, login, subscription or tracking.
- Any uncalibrated model confidently declaring a user's memory redundant or worthless.
