# N05 Never Suggest / Protection Rules: Implementation Plan

Planner: read-only audit of HEAD `f694156` on 2026-11-12. The working tree has `App/Views/SwipeSaveView.swift` modified and `UITests/RealLibrarySmokeUITests.swift` untracked. Both belong to another agent. Do not stage them.

## 0. Gate before coding

`docs/HANDOFF.md` §"Known failures" says: *"Do not start N05 implementation while fixable current regressions remain."* Another executor is fixing the Home/Swipe accessibility audits now. Options:

- **Recommended:** start N05 after those fixes land on `main`.
- **Alternative, orchestrator's call:** C1–C3 touch no UI files, so they could start now on branch `feature/N05-protection-rules`.

**Safety gate (owner):** C1 adds a hard `PreservationFlag`, and C4 and C5 change the deletion coordinator and tray revalidation. AGENTS.md says push authorization does not cover safety-policy changes. Recommendation:

- Do all N05 work on `feature/N05-protection-rules`. Pushing the branch is allowed.
- Do not merge to `main` until the owner reviews the C1, C4 and C5 diff. Record that review as PENDING.

**Simulators:** the other executor uses the booted iPhone 17 Pro (`0C142434…`). Run N05 xcodebuild tests on iPhone 17 Pro Max (`8D13E1E4…`) and iPad Pro 11-inch (M5) (`068BE719…`). Never run two test sessions on one simulator.

## 1. Phase 0 audit (from source)

| Item | Source reality |
|---|---|
| Min OS / devices | iOS 26.0 app (`project.yml`), Core package `.iOS(.v18), .macOS(.v14)`, `TARGETED_DEVICE_FAMILY 1,2`, multiple scenes disabled, Swift 6 with strict concurrency set to complete |
| SafetyPolicy | `Core/Sources/CleanSlateCore/SafetyPolicy.swift`: `evaluate`, `hardBlocked`, `validateCommit`. Also `validateStandalone` (StandalonePolicy.swift) and `validateBatch` with `maximumBatchTargets = 500` (BatchPolicy.swift). Hard set in `Models.swift` `PreservationFlag.hard` |
| Allowed policy callers | `scripts/check_policy_separation.sh` allows `validateCommit` only in `func commit(` and `reasonNeedingAnotherLook(_ entry: TrayEntry)`, `validateStandalone` only in `commitStandalone(` / `reasonNeedingAnotherLook(_ entry: StandaloneTrayEntry)` / `evaluate(groups:`, and `validateBatch` only in `evaluate(groups:`. It requires exactly one `deleteAssets` |
| Single delete | `PhotoKitLibraryClient.delete(ids:expectedRevisions:)` line 129 is the only `deleteAssets`. The coordinator calls `library.delete(` three times: `commit` (99), `commitStandalone` (157), `commitBatch` (241). **Production uses only `commitBatch`** (via `DeletionTray.deleteAll`). The other two are reached only from tests, but must still be gated |
| Commit revalidation | `commitBatch`: `evaluate()` (fresh `snapshot(id:inspectAlbums:true)` + `validateBatch` / `validateStandalone`), then rehash exact groups, then `evaluate()` again, then the auth guard, then `library.delete`. There is **no `await` between the second `evaluate` and `library.delete`** |
| Album protection already exists | `PhotoKitLibraryClient.makeSnapshot(inspectAlbums:true)` marks `.curatedAlbum` (hard) for **any** `.album` membership. `ScanEngine.markAlbum` does the same at grouping, and standalone hides `albumMembers` |
| Tray | `DeletionTray` stores JSON (`tray.json`). `needsAttention` is **in memory only** and fully recomputed by `CleaningViewModel.revalidateTray(touched:)` via `TrayChecker` (in `GroupRechecker.swift`) |
| Store | `LibraryStore`: `static let schemaVersion = 1` is **hard-coded**, `migrations` has one entry, so `user_version = 1`. `reset()` deletes an explicit table list. `CleaningViewModel.init` **silently falls back to an in-memory store** if the on-disk open fails (line 142) |
| Suggestion producers | ScanEngine produces exact groups (`verifyExactCopies`), review sets (`buildReviewSets`), similar pairs (`compareSimilarPairs`) and standalone items (`findStandaloneItems`). All groups enter the view model through `CleaningViewModel.didChangeGroups(added:)`: scan flush, `GroupRechecker`, and `seedGroupsForUITesting`. Standalone items enter through `didChangeStandalone`, then `recomputeStandalone`, then `StandaloneRules.items` (which requires `flags.isEmpty`) |
| Approval ingress | `GroupReviewModel.approve` (also used by `SwipePairModel`), `CategoryGroupsView` approve-all (`SafetyPolicy.evaluate(...).preselected`), `StandaloneListView` → `tray.approveStandalone` |
| Settings UI | No Settings screen. A gear `Menu` in `DashboardView` (`dashboard.menu`) pushes `DiagnosticsView` through `navigationDestination` |
| Feature flags | None exist. The closest pattern is `LabelStore.isAvailableInThisBuild` |
| Fakes | `FakePhotoLibrary` (`App/Debug`) has `deleteCalls`, `onDigests`, `beforeDelete`, `albumMemberTable`. **`snapshot(id:inspectAlbums:)` ignores `inspectAlbums`** (fidelity gap). UI fake mode is `-uiTestingFakeLibrary -skipOnboarding [-uiTestingSwipe] [-uiTestingAuth limited]`, with an in-memory store and a `org.cleanslate.uitest` defaults suite |
| Test targets | Core SwiftPM `CleanSlateCoreTests` (Linux-safe), `CleanSlateTests` (iOSTests, hosted, fake env), `CleanSlateUITests` |

### Spec claims that contradict source

1. **Album rules add no deletion safety today.** Every album member is already hard-blocked as `.curatedAlbum`. Under limited access, `fetchAssetCollectionsContaining` likely returns no user albums, so `.curatedAlbum` may silently not be set. That is a **pre-existing possible fail-open** (UNVERIFIED; Apple's limited-access docs could not be fetched). Raise it with the owner separately; it is not N05 scope. **Decision: defer album-rule UI.** Keep the `album` kind in the schema and Core evaluator, failing closed.
2. Spec places `verdict(asset: PhotoSnapshot)` in Core, but `PhotoSnapshot` is an App type. Core uses a primitive `ProtectionSubject`.
3. Spec's `PhotoAuthorizationScope` does not exist. The source uses `PHAuthorizationStatus`.
4. Spec says "pause the in-flight commit." The commit is `@MainActor` with a synchronous final check, so we **block and report** instead of pausing.
5. Spec says "Needs Attention" is enough to stop resurrection. It is not: `needsAttention` is recomputed, so removing a rule or relaunching would resurrect entries. A **persisted sticky set** is required.
6. Spec assumes the store is authoritative. The silent in-memory fallback would read "zero rules" and fail open. This needs a sentinel (C3).
7. Spec's permission-free demo, local impact counters, category-level "do not suggest", "dismissed once" and media-type rules have no infrastructure. **Deferred.** Favorites are already hard.
8. `schemaVersion` must be bumped by hand. `testDataSurvivesReopenAndMigrationRunsOnce` asserts it.

## 2. Scope of this increment

**In scope (simulator-testable):**
- Per-asset "Never suggest".
- Inclusive local-date-range rules.
- Durable rules with fail-closed load.
- Suggestion filtering (groups, Swipe feed, approve-all, standalone lists).
- Approval guards.
- Tray invalidation that sticks.
- Commit-time revalidation with a rule-revision check.
- iPhone sheet and rules screen.
- iPad inspector, keyboard and pointer support.

**Deferred or PENDING:**
- Album rules UI and full-access album membership.
- Limited-access album explanation with `presentLimitedLibraryPicker` (verified in `PhotosUI/PHPhotoLibrary+PhotosUISupport.h:35,45`).
- Demo gallery, counters, category preferences.
- All device gates.

## 3. Design

**Recommendation: an evaluation-time hard overlay flag.**
- Add `PreservationFlag.userProtected` to `PreservationFlag.hard`.
- An App-level `ProtectionGate` derives it from the authoritative rule store and applies it to **fresh** snapshots right before every existing policy call. It is never persisted.
- This follows the existing `.curatedAlbum`/`markAlbum` precedent. `validateCommit`, `validateBatch`, `validateStandalone`, `evaluate`, `ReviewDraft.protectedIDs` and the existing all-flags tests (`testHardFlagsAlwaysBlock`, `testAllFlagsAreClassifiedExactlyOnce`, `testEveryFlagBlocksBecauseThereIsNoKeeper`, `testAllPreservationFlagsBlockEitherDeletionDirection`) all enforce it with no edits to existing assertions.
- Indeterminate verdicts overlay the existing hard `.uncertainMetadata`.

Rejected alternatives:
- A separate coordinator-only check: it needs about 10 hand-placed hooks, and a missed hook fails open.
- Wrapping the `PhotoLibraryClient`: it breaks `as? FakePhotoLibrary` probes and does not cover store-sourced snapshots.
- Persisting the flag in `assets.flags`: it conflates PhotoKit metadata with user intent, which the spec forbids.

### 3.1 Core types: `Core/Sources/CleanSlateCore/ProtectionRules.swift`

All types are `Sendable`, and `Codable` where they are persisted.

```swift
public struct LocalDay: Hashable, Comparable, Codable, Sendable { year, month, day; init?(_ iso: String) /* strict yyyy-MM-dd, calendar-valid */; var iso: String }
public enum ProtectionScope: Codable, Equatable, Sendable {
  case asset(localIdentifier: String)
  case album(localIdentifier: String)                       // schema/Core only this increment
  case dateRange(start: LocalDay, end: LocalDay, timeZoneID: String, startInclusive: Date, endExclusive: Date)
}
public struct ProtectionRule: Codable, Equatable, Identifiable, Sendable { id: UUID; scope; enabled: Bool; createdAt: Date; updatedAt: Date }
public struct ProtectionSubject: Sendable { id: String; capturedAt: Date?; albumIDs: Set<String>? /* nil = unknown */ }
public enum IndeterminateReason: String, Sendable { case rulesUnavailable, rulesLoading, ruleWritePending, albumMembershipUnknown }
public enum ProtectionVerdict: Equatable, Sendable { case unprotected, protected(ruleIDs: Set<UUID>), indeterminate(IndeterminateReason) }
public enum ProtectionAvailability: Equatable, Sendable { case loading, ready, unavailable(String), lost }
public enum ProtectionDateResolver { static func interval(start:end:timeZoneID:) -> (Date, Date)? }
public struct ProtectionRuleSet: Sendable, Equatable { init(rules:revision:) throws; func verdict(_:) -> ProtectionVerdict; let revision: Int64 }
public enum ProtectionCommitGate { static func block(availability:pendingWrites:startRevision:currentRevision:) -> IndeterminateReason? }
public enum ProtectionLoadPolicy { static func availability(read: Result<Int64, Error>?, everCreated: Bool, mirroredRevision: Int64, storeDurable: Bool) -> ProtectionAvailability }
```

**`ProtectionRuleSet`:**
- `init` rejects rules with an empty asset id, `end < start`, an unknown time zone, `endExclusive <= startInclusive`, or more than 5,000 asset or 100 date rules. These throw, so a bad set becomes `unavailable` (fail closed). Disabled rules are ignored.
- Build: the asset index is `[String: Set<UUID>]`. Date intervals are sorted by start and merged when overlapping or touching, each keeping the union of its IDs. The album index is built the same way as the asset index. Cost is O(R log R) time and O(R) memory.
- `verdict(s)`:
  1. Look up the asset index by `s.id`.
  2. If `capturedAt` is non-nil, binary-search the last interval with `start ≤ t`, and match if `t < end`. A nil date never matches.
  3. If album rules exist: when `albumIDs` is nil and nothing matched yet, return `.indeterminate(.albumMembershipUnknown)`. Otherwise look up each album id.
  4. Return `.protected(ids)` or `.unprotected`.
- Cost per query is O(1 + log D + |albums|). Protected wins over indeterminate.

**`ProtectionDateResolver`:** use a Gregorian calendar in the rule's time zone. Take `startOfDay(noon(start))` and `startOfDay(noon(end) + 1 day)`. The noon anchor handles days with no midnight.

**`ProtectionCommitGate.block`:** return non-nil if availability is not `.ready`, if `pendingWrites > 0`, or if the revision changed. Precedence for explanations: hard flags, then asset rule, then date or album rule, then conditional flags. All of these block.

### 3.2 Migration v1 → v2 (`LibraryStore.migrations[1]`)

```sql
CREATE TABLE protection_rules(
  rule_id TEXT PRIMARY KEY,
  kind TEXT NOT NULL CHECK(kind IN ('asset','album','date_range')),
  target_id TEXT,
  start_local_day TEXT, end_local_day TEXT,
  calendar_id TEXT NOT NULL DEFAULT 'gregorian', time_zone_id TEXT,
  start_utc REAL, end_utc_exclusive REAL,
  created_at REAL NOT NULL, updated_at REAL NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0,1)),
  rule_version INTEGER NOT NULL DEFAULT 1,
  CHECK((kind IN ('asset','album') AND target_id IS NOT NULL AND start_local_day IS NULL) OR
        (kind='date_range' AND target_id IS NULL AND start_local_day IS NOT NULL AND end_local_day IS NOT NULL
         AND time_zone_id IS NOT NULL AND start_utc IS NOT NULL AND end_utc_exclusive IS NOT NULL
         AND end_utc_exclusive > start_utc AND end_local_day >= start_local_day)));
CREATE UNIQUE INDEX protection_unique_target ON protection_rules(kind, target_id) WHERE target_id IS NOT NULL;
CREATE UNIQUE INDEX protection_unique_range ON protection_rules(start_local_day, end_local_day, time_zone_id) WHERE kind='date_range';
CREATE TABLE protection_rule_revision(singleton INTEGER PRIMARY KEY CHECK(singleton=1), revision INTEGER NOT NULL);
INSERT INTO protection_rule_revision VALUES (1,1);
```

Store API rules:
- Set `static var schemaVersion: Int { migrations.count }`.
- New methods **throw** rather than return `try?`-style empty results: `protectionRules() throws -> (revision: Int64, rules: [ProtectionRule])`, `insertProtectionRules([ProtectionRule]) throws -> Int64` (`INSERT OR IGNORE`; bump the revision only if rows changed), `deleteProtectionRule(id:) throws -> Int64`, `deleteAllProtectionRules() throws -> Int64`, and `protectedRangeIndexedCount(start:end:) -> Int` (a `COUNT` on `assets.created_s` with `deleted=0`).
- Each write is one `transaction { rows + UPDATE revision }`.
- `reset()` stays unchanged and does **not** touch protection tables.
- `upsert` strips `.userProtected` before writing flags.
- Test seams (internal): `init(path:maximumVersion:)`, and `debugExecute(_ sql:)` behind `#if DEBUG`.

### 3.3 App service: `App/Services/ProtectionRuleService.swift`

- `@MainActor protocol ProtectionGate: AnyObject { availability; revision; pendingWrites; func verdict(for: PhotoSnapshot) -> ProtectionVerdict }`. The verdict returns `.indeterminate` when availability is not ready or a write is pending.
- Extension methods: `decoratedRecord(_:)`, `decorated(_:)` (adds `.userProtected` or `.uncertainMetadata`), and `commitBlock(since:)` (calls Core `ProtectionCommitGate`).
- `final class ProtectionRuleService: ObservableObject, ProtectionGate` publishes `availability`, `rules`, `revision` and `lastError`. It has `load()`, `protect(assetIDs:)`, `protect(range:)`, `remove(ruleID:)`, `removeAll()`, `acknowledgeLost()`, and `onChange: ((ProtectionChange) -> Void)?`.
- **Write protocol:**
  1. `pendingWrites += 1` (synchronous).
  2. Set `defaults["protection.everCreated"] = true` *before* the await.
  3. Await the store write.
  4. On success, rebuild the rule set, set `revision`, mirror `protection.lastRevision`, call `onChange`, then `pendingWrites -= 1`.
  5. On failure, decrement and set `lastError`. The UI is never shown as protected before the commit succeeds.
- Writes are refused (with an error) when `requiresDurableStore && store.path == nil`.
- **Load:** `ProtectionLoadPolicy` decides the state:
  - If the read throws or the store is not durable: `unavailable` when everCreated is true, otherwise `ready` with an empty set.
  - If the DB revision is below the mirrored revision and everCreated is true: `lost`. This covers a replaced DB or a backup restore, since UserDefaults is backed up and the DB is not.
- `App/Services/FeatureFlags.swift`: `protectionRulesUI` is `true` in DEBUG unless `-disableProtectionRulesUI` is passed, and `false` in Release. **Enforcement is never behind the flag.** The rules screen stays reachable whenever rules exist or availability is not `.ready`, so a `lost` or `unavailable` state never leaves the user stuck.

### 3.4 Enforcement points (no new delete call)

1. **Commit** (`PhotoDeletionCoordinator`). Add `init(library:networkPolicy:protection:)` with `protection` **required**.
   - In each of `commit`, `commitStandalone` and `commitBatch`: capture `let ruleRev = protection.revision` after `activeCommit = true`, and throw the new `DeletionError.protectionUnavailable` if `commitBlock` is non-nil.
   - Every fresh `snapshot(...).record` becomes `protection.decoratedRecord(snapshot)`. That covers both loops in `commit`, the loop in `commitStandalone`, and `load` in `evaluate()`.
   - In `evaluate()`, entries whose selected ids carry `.userProtected` get reason `TrayChecker.protectedByRuleReason`.
   - Immediately after the final `guard hasAccess` and before `library.delete`, with no `await` between: `if protection.commitBlock(since: ruleRev) != nil { throw .protectionChanged }`.
   - Messages:
     - "Protection rules couldn't be checked. Nothing was deleted."
     - "Your protection rules changed while checking. Nothing was deleted. Tap Delete again."
2. **Queued tray/draft revalidation.**
   - `TrayChecker(library:protection:)` decorates fresh records. A selected id that is user-protected returns `protectedByRuleReason`, checked before the policy. While `.loading`, the rule check is skipped and is not sticky.
   - `DeletionTray` gets a persisted `protectionInvalidatedIDs` (optional field in `Stored`). `readyEntries` and `readyStandaloneEntries` exclude it. It is cleared only by `sendBackToReview`, `remove`, `clear`, or re-`approve` of the same id.
   - `revalidateTray` inserts ids with the protected reason and always re-applies the reason for sticky ids. `deleteAll` `.blocked` reasons equal to `protectedByRuleReason` also become sticky.
   - On `onChange(.added)`, `CleaningViewModel` computes the tray ids whose *stored* snapshots now match (O(T), no PhotoKit), then calls `revalidateTray(touched:)`. On `.reloaded` it calls `revalidateTray(nil)`.
3. **Suggestion generation** (`CleaningViewModel`).
   - Keep `sessionShieldedIDs`, cleared in `resetResults()`, so protection only grows within a session. A protected verdict adds the id.
   - `didChangeGroups(added:)` decorates each group. If `SafetyPolicy.evaluate(decorated)` has no preselected or review-only ids but the undecorated group did, the group is withheld, recorded in `hiddenByRulesGroupIDs`, and removed if already present.
   - On a rule change, redecorate all groups. Removing a rule takes effect at the next scan: no new suggestions mid-session.
   - `recomputeStandalone` hides items that are shielded by verdict or session. `selectionBlockReason` decorates the fresh snapshot.
   - Add an `approveStandalone(_:) -> Bool` guard.
   - `GroupReviewModel(…, protection:)`: `approve()` blocks if not ready or if any `deleteIDs` verdict is not `.unprotected`, with notice "Protected by your rule — always kept".
   - `SwipePairModel.freshSnapshotsMatch` compares against the decorated fresh record.
   - The `ReviewSessionView.token` includes sorted flags, so a newly protected group re-opens. Groups hidden by rules show "Kept safe by your rule. Nothing was deleted."
   - `CategoryGroupsView` hides approve-all when not ready.
   - Add `userFacingReason` for `.userProtected`: "Protected by your rule — always kept". Add a `PhotoTile` trait symbol `lock.shield.fill` labelled "Protected by your rule".

## 4. UX

**iPhone**
- **Entry points:**
  - ReviewGroupView: an item in the "More" menu ("Never suggest a photo…", `review.protect`), a tile context menu plus `accessibilityAction(named: "Never suggest")` (`protect.action.<id>`).
  - StandaloneListView: item context menu and accessibility action (`standalone.protect.<id>`).
  - CompareView toolbar (`compare.protect`).
  - SwipeSaveView toolbar (`swipe.protect`), in C8.
  - DashboardView gear menu: "Protected photos" (`menu.protection`), which pushes `ProtectionRulesView` (same pattern as Diagnostics).
- **`ProtectSheet`** (`protect.sheet`):
  - Scope picker `protect.scope`: "Just these photos" or "Photos from these dates".
  - Photo toggles with thumbnails (`protect.photo.<id>`).
  - Date pickers prefilled from the selected photos (`protect.range.start` / `.end`), disabled when no date exists, with "N checked photos in this range".
  - Body: "CleanSlate won't suggest deleting these on this device. Apple Photos isn't changed."
  - Buttons: `protect.confirm` ("Protect", which shows "Saving…" via `protect.saving`) and `protect.cancel` (`.keyboardShortcut(.cancelAction)`, verified in SwiftUI.swiftinterface:27014). Errors show in `protect.error`.
  - On success, a tray toast: "Protected. CleanSlate won't suggest it." with Undo, which removes the rule. Expose `DeletionTray.showToast(_:undo:)`; no AppTabsView edit is needed.
- **`ProtectionRulesView`** (`protection.screen`):
  - Sections `protection.section.photos` and `protection.section.dates`.
  - Rows `protection.rule.<uuid>`. Inaccessible assets show "Not available right now".
  - Removal through a visible button `protection.rule.<uuid>.remove` plus swipe. The confirm dialog `protection.remove.confirm` says: "It may be suggested again after your next scan. Nothing is deleted."
  - Toolbar: `protection.addRange`, and `protection.removeAll` (confirm only, no keyboard shortcut).
  - States: `protection.loading`, `protection.empty`, `protection.unavailable` (with `protection.retry`), `protection.lost` (with `protection.lost.continue`, confirm required), and `protection.limitedBanner` ("Protected photos you haven't shared still stay protected.").
- **Tray:** banner `tray.protectionBlocked` when not ready, with a "Fix" link to the rules screen. The Delete button is disabled.

**iPad** (separate composition in the same view file or `ProtectionRulesView+Wide`):
- When `horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize`: a selectable List plus `.inspector(isPresented:)` / `.inspectorColumnWidth(ideal: 320)` (verified in SwiftUI.swiftinterface:14722–14724) hosting `ProtectionRuleDetailView` (`protection.inspector`). The detail shows coverage count and Remove.
- Compact, Stage Manager narrow, or AX sizes: push `protection.detail`.
- Selection kept in `@SceneStorage("protection.selectedRule")`.
- Search: `.searchable(text:isPresented:)` (verified :7336) over rule type and date text only, plus a Cmd-F toolbar button `protection.search`. Whether `.searchable` binds Cmd-F on its own is UNVERIFIED.
- Pointer right-click uses the same context menus. Hover never mutates.

## 5. Commits (do in order on `feature/N05-protection-rules`; write tests first)

| # | Files | Tests written first | Acceptance |
|---|---|---|---|
| **C1** Core types + flag (OWNER GATE) | `Core/Sources/CleanSlateCore/ProtectionRules.swift` (new), `Models.swift` (add `userProtected` to `hard`), `App/Models/GroupReviewModel.swift` (`userFacingReason` case only, so it compiles) | `Core/Tests/.../ProtectionRuleSetTests.swift`, `ProtectionDateResolverTests.swift`, append-only `SafetyPolicyTests`: `testUserProtectedIsHard`, `testUserProtectedKeeperRemainsValidKeeper`, `testUserProtectedTargetFailsCommit` | `make core-test` green. No existing assertion edited. `make verify` (Linux) or a note if tzdata is missing |
| **C2** Migration v2 + CRUD | `App/Store/LibraryStore.swift` | `iOSTests/ProtectionStoreTests.swift` | v1→v2 keeps rows. Existing `testDataSurvivesReopen…` passes with schemaVersion 2 |
| **C3** Service + gate + flag | `App/Services/ProtectionRuleService.swift`, `App/Services/FeatureFlags.swift`, `iOSTests/Support/StaticProtectionGate.swift` | `iOSTests/ProtectionServiceTests.swift`, Core `ProtectionLoadPolicyTests` | State machine, sentinel and pending writes proven |
| **C4** Commit enforcement (SAFETY REVIEW) | `App/Services/PhotoDeletionCoordinator.swift`, the 6 coordinator init sites (`CleaningViewModel` + 5 tests) | `iOSTests/ProtectionCommitTests.swift` | Gherkin 2 passes. `make lint` passes (one `deleteAssets`). `grep -c "library.delete(" App/Services/PhotoDeletionCoordinator.swift` = 3 |
| **C5** Queued revalidation | `GroupRechecker.swift` (TrayChecker), `DeletionTray.swift`, `CleaningViewModel.swift` (owns `protection`, `onChange`), `GroupReviewModel.swift`, `SwipePairModel.swift` | `iOSTests/ProtectionTrayTests.swift`, `GroupReviewProtectionTests.swift` | Gherkin 1 and 4 pass |
| **C6** Suggestion filtering | `CleaningViewModel.swift`, `StandaloneListView.swift`, `CategoryGroupsView.swift`, `ReviewSessionView.swift`, `PhotoTile.swift` | `iOSTests/ProtectionSuggestionTests.swift` | Protected items never preselected or listed. Existing fav-group UI tests unchanged |
| **C7** iPhone UI | `App/Views/ProtectSheet.swift`, `ProtectionRulesView.swift`, `ReviewGroupView.swift`, `CompareView.swift`, `TrayView.swift`, `DashboardView.swift` (**after the a11y commit lands; rebase**), `CleanSlateApp.swift` (fake args `-uiTestingProtectedAssets a,b`, `-uiTestingProtectionUnavailable`, `-uiTestingProtectionStore`) | `UITests/ProtectionUITests.swift` | Flows, AX3/AX5 and `performAccessibilityAudit` pass. Screenshots in `docs/screens/n05/` |
| **C8** Swipe entry | `SwipeSaveView.swift` toolbar only (after the concurrent edit merges) | `ProtectionUITests.testSwipeNeverSuggest…` | Existing Swipe audits still pass |
| **C9** iPad | `ProtectionRulesView` wide layout, `AdaptiveLayout` helper | `UITests/ProtectionIPadUITests.swift` | Rotate/resize keeps selection. Escape cancels. No remove-all shortcut |
| **C10** Docs | `PROGRESS.md`, `VALIDATION_LOG.md`, `RELEASE_CHECKLIST.md`, `HANDOFF.md`, N05 spec status | — | Evidence recorded honestly. Gates marked PENDING |

The C7 UI work must follow the `apple-skills` design and ux-writing rules (EXECUTION_PLAN §0.1 rule 10) and the §0.3 UI review.

## 6. Acceptance test matrix

| ID | Scenario | Test (target) | Expected |
|---|---|---|---|
| G1 | Protect after tray approval | `ProtectionTrayTests.testProtectingTargetMarksNeedsAttentionBeforeAnyDelete` (iOS). UI: `ProtectionUITests.testProtectAfterApproveShowsNeedsAnotherLook` | Entry under `tray.attention` with "Protected by your rule". `deleteCalls` empty. Probe `deleteCalls=0` |
| G2 | Rule created during rehash | `ProtectionCommitTests.testRuleCreatedDuringRehashBlocksBatch` (via `onDigests`), `…BlocksSingleCommit`, `…BlocksStandalone` | Throws `.protectionChanged`. `deleteCalls` empty |
| G3 | Unknown album membership | Core `testAlbumRuleUnknownMembershipIsIndeterminate`. iOS `testAlbumRuleRowBlocksAllCommits` (row injected via `debugExecute`) | `.indeterminate`. Commit blocked. The access-management explanation is **PENDING** (album UI deferred) |
| G4 | Removing a rule doesn't resurrect | `ProtectionTrayTests.testRemovingRuleKeepsEntryNeedingReview`, `testStickyInvalidationSurvivesTrayReload` (on-disk tray). UI `testRemoveRuleDoesNotRestoreTrayEntry` | Entry stays out of `readyEntries` until Review again or Remove |
| E1 | Rules unreadable after rules were created | `ProtectionServiceTests.testReadFailureWithPriorRulesIsUnavailable`, `ProtectionCommitTests.testUnavailableBlocksAllDeletion` | `.protectionUnavailable`. Nothing deleted |
| E2 | Store fallback, rules never created | `testFallbackStoreWithoutPriorRulesDoesNotRegressDeletion` | `ready`. Existing batch deletes |
| E3 | DB lost or restored from backup | `testRevisionBelowMirrorIsLostUntilAcknowledged` | `lost` blocks deletion. `acknowledgeLost` gives `ready` |
| E4 | Malformed row (bad local day) | `ProtectionStoreTests.testMalformedRowFailsClosed` | `unavailable` (not skipped) |
| E5 | Write fails | `testFailedWriteLeavesUnprotectedWithError` (`debugFailNextProtectionWrite`) | `lastError` set. Verdict stays `.unprotected`. No shield shown |
| E6 | Pending write at commit | `ProtectionCommitTests.testPendingWriteBlocksCommit` | Blocked |
| E7 | Any revision change mid-commit, including a removal | `testRuleRemovalDuringCommitStillBlocks` | Blocked (fail closed) |
| E8 | Asset edited after rule | Core `testAssetRuleIgnoresRevision`. iOS `testEditedAssetStaysProtected` | Still protected |
| E9 | Stale open draft | `GroupReviewProtectionTests.testApproveFromStaleDraftIsBlocked` | `approve()` false. Tray empty |
| E10 | Swipe both orientations | `ProtectionSuggestionTests.testProtectedPhotoBlocksReversedSwipe`, `testProtectedKeeperAllowsDeletingOther` | Reversed orientation blocked. Keep-protected approves |
| E11 | Approve-all | `testApproveAllSkipsUserProtectedCopies` | Protected copy is not in the tray |
| E12 | Standalone screenshot | `testProtectedScreenshotHiddenAndNotCommittable` | Hidden from the list. `commitStandalone` throws `.unsafe("protected")` |
| E13 | Unprotect mid-session | `testRemovingRuleDoesNotRemarkExactCopyInSession` | Group stays withheld until the next scan |
| E14 | Over 500 targets, protected item in chunk 2 | `testProtectedTargetInLaterChunkNeverDeleted` | No `deleteCalls` entry contains it |
| E15 | Cancel during rehash with a pending rule | `testCancelDuringRehashWithPendingRuleDeletesNothing` | Stopped. Nothing deleted |
| E16 | DST and boundaries | Core `testInclusiveEndDay`, `testNewYorkFallBack2026_11_01`, `testSpringForward2026_03_08`, `testMidnightlessDaySaoPaulo2018_11_04`, `testNilDateNeverMatches`, `testEndBeforeStartRejected`, `testUnknownTimeZoneRejected` | As named |
| E17 | Limited library, inaccessible asset | `testRuleForInaccessibleAssetKeptAndShownUnavailable`. UI `testLimitedShowsBanner` (`-uiTestingAuth limited`) | Rule kept. Row "Not available right now" |
| E18 | Clear saved scan data | `ProtectionStoreTests.testResetPreservesRules` | Rules and revision intact |
| E19 | Overlay never persisted | `testUpsertStripsUserProtectedFlag` | `assets.flags` never contains it |
| E20 | Migration with real rows | `testMigrationFromV1PreservesRowsAndCreatesProtectionTables` (open with `maximumVersion:1`, upsert assets/features/digests/meta/receipt, reopen, `PRAGMA integrity_check`) | `user_version = 2`. All rows equal. Revision 1 |
| E21 | Old-binary compatibility | `testV2DatabaseOpenedWithV1MigrationListIsUntouched` | No throw. `user_version` stays 2 |
| E22 | Duplicate protect (double tap) | `testDuplicateAssetRuleIdempotent` | One row. One revision bump |
| E23 | Flag off | `ProtectionServiceTests.testFlagOffStillEnforces`. UI `testFlagOffHidesProtectEntryPoints` | Enforcement on. Entry points hidden. Rules screen shown if rules exist |
| E24 | Deleted album | Core `testAlbumRuleKnownMembershipWithoutAlbumIsUnprotected` | PENDING in App (deferred) |
| E25 | iPad | `ProtectionIPadUITests.testRotateKeepsSelectedRule`, `testNarrowWindowPushesDetail`, `testEscapeCancelsSheet`, `testAX5CollapsesInspector` | As named |

Commands: `make core-test fixtures-test eval lint build`, then targeted `-only-testing:CleanSlateTests/Protection*` and `CleanSlateUITests/Protection*` on the simulators named above, then the full `make ios-test` before C10.

## 7. Risks, residuals and PENDING items

- **Residual window:** a rule written after `library.delete` has been entered (that is, while Apple's prompt is showing) cannot stop that request. The UI is covered by the system alert at that point. Document it; there is no test for it.
- **Residual (fix round 1, M2c):** if BOTH the rule database file and the UserDefaults sentinel are wiped or replaced (for example a full app-container reset), rules are gone and the app cannot tell. It then behaves like a fresh install. Not detectable without an external store; documented, not fixed.
- **Residual (m4):** a photo with no creation date never matches a date-range rule (spec-intended, see N05 §7). Asset rules still protect it.
- **Residual (m3):** a local day that does not exist in the chosen time zone (for example Samoa 2011-12-30) is rejected when creating a date rule instead of being widened.
- - **Downgrade:** an older binary ignores rules. Old tray JSON decoding fails on the new flag, which empties the tray (fail-safe). Owner awareness needed.
- **Perf:** redecorating on rule change is O(G·m) on the main actor. Measure with the 10k fake library (watchdog under 250 ms).
- **PENDING (owner/device):**
  - Owner safety review of the C1, C4 and C5 diff before merging to `main`.
  - Physical-device canary with a disposable library: a protected target is never deleted, rules persist across relaunch, the limited-access screen is correct.
  - iPad hardware keyboard and pointer.
  - Whether the flag is enabled for TestFlight (owner decision).
  - Independent gatekeeper.
  - Limited-access `.curatedAlbum` behavior (pre-existing, UNVERIFIED).
- **UNVERIFIED:** Apple's limited-access album fetch semantics (docs page not retrievable). `.searchable` Cmd-F binding. Linux tzdata for Core date tests.

## 8. Recommended next action

The orchestrator confirms the a11y fixes have landed, or explicitly allows parallel Core-only work. It then briefs the executor for **C1** on `feature/N05-protection-rules` and schedules the owner safety review before any merge to `main`.

## Continuation checkpoint (2026-11-12)

Claude completed C1–C9 through 410b924; main9037790 was reconciled before this continuation. C10 documentation and calendar/time-zone, presentation-metadata, adaptive-layout and accessibility fixes are recorded in [N05_REVIEW_PACKET.md](N05_REVIEW_PACKET.md). Original planner assumptions above are retained as historical rationale; the V2 package is now present. This checkpoint does not close owner C1/C4/C5 review, full N05 scope, the physical-device matrix or release. Read the latest VALIDATION_LOG entry for failures, focused fixes and exact measured results; an earlier full failing run is not a final CI pass.
