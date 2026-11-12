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
