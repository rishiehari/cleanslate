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
