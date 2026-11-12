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
