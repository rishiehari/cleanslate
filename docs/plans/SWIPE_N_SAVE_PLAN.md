# Swipe n Save: full product and implementation plan

Date: 2026-11-11. Status: owner-requested expanded requirements; minimal two-photo similar-review V1 is being implemented separately. This plan is not evidence that every capability below exists. Current work is tracked in `docs/features/S01-swipe-n-save.md` and `docs/PROGRESS.md`. No device gate is marked complete by this document.

## Outcome and scope

A short, pleasant review session: see two matching or closely similar photos, choose which stays, or keep both. Build confidence from the first useful pair. “Swipe n Save” is the owner-selected feature name; the interface must not imply that swiping instantly recovers storage.

Requested full interaction: **swipe left keeps the left photo, swipe right keeps the right photo, swipe up or tap the center button keeps both.** Visible buttons always provide the same actions. Include both verified exact pairs and closely similar pairs. Support Compare, Undo, leaving/resuming, warnings, and the existing tray.

Recommended conservative default: a horizontal swipe stages Keep/Delete; a separate **Approve** button adds the chosen removal to the tray and advances. Keep both advances immediately with Undo and adds nothing. This keeps the existing Review → Approve → Tray → Delete contract obvious and avoids accidental swipe approval identified in the earlier prototype review. A future swipe-to-approve shortcut is a separate UX decision requiring evidence; it is not part of this plan's default.

No streak penalties, countdown pressure, confetti for deletion, notifications, account, leaderboard, server learning or auto-delete. A “A few minutes is enough” invitation and “Done for now” action support the daily habit without coercion. Five minutes is an invitation, not a claimed runtime or obligation.

## Current foundation versus planned capability

| Capability | Current foundation | Planned work |
|---|---|---|
| Two-photo similar feed | ScanEngine emits native `near-*` pairs after Vision distance <0.32; `.similar` also includes burst/time review sets | Minimal V1; preserve honest provenance |
| Exact pairs | Full-resource equality, exact group preselection and commit rehash already exist | Add exact-pair presentation with an explicit pair choice |
| Larger groups | SequenceGrouping and group review exist, multiple keepers supported | Pair sessions with explicit parent/subset accounting; later phase |
| Left/right and Keep both | New minimal V1 model/views in progress | Add up gesture and consistent directional feedback where not already shipped |
| Approve/tray/undo | Persistent tray and existing coordinator | Reuse; draft persistence and pair-level undo need explicit coverage |
| First-value onboarding | Existing three-page onboarding and Home permission card | Short practice + first-pair guidance; F04 scoped scan remains separately gated |
| Calibration | Hand-set KeeperRanker v1, offline fitter, ML_GATE OFF | Optional local ranking/conservative feed preference, off by default |
| iPad | iPhone-only target | Adaptive layout and input per IPAD_APP_PLAN.md; no iPad code in current scope |

## Product requirements

| ID | Requirement | Acceptance summary |
|---|---|---|
| SW01 | Explicit directional meaning | Left/right retain the photo visibly labeled Left/Right; layout changes never invert the choice. |
| SW02 | Both exact and close similar pairs | Exact badge requires full resource proof; similar badge never claims identity or calibrated confidence. |
| SW03 | Keep both | Up/center button leaves both photos, adds no tray item, supports Undo. |
| SW04 | Approve is separate from deletion | No swipe, choice, approval, tab switch or animation calls PhotoKit delete. |
| SW05 | Similar starts undecided | No similar photo is marked Delete before explicit choice; ranking does not select deletion. |
| SW06 | Warnings and protections in both directions | The chosen loser is evaluated regardless of original suggested keeper; protected targets cannot be selected. |
| SW07 | Fresh visible evidence | A changed pair invalidates draft/acknowledgment; rechecking disables approval; commit revalidates again. |
| SW08 | Resumable and reversible | Pause/leave/tab switch retains valid draft; relaunch validates restored state; undo restores the pair without stale authorization. |
| SW09 | Honest impact | Session shows reviewed pairs and photos ready in tray; verified savings appear only with appropriate receipt wording. |
| SW10 | Optional personalization | Explicit opt-in, local and resettable, never changes preservation policy or authorizes deletion. |
| SW11 | Accessible interaction | Buttons, VoiceOver actions, large text and Reduce Motion; keyboard equivalents on iPad. |
| SW12 | Bounded workload | Reuse existing results; no full-library pair computation in view rendering; bounded images/history. |

## The first session

1. Landing: “Choose the photo you want to keep.” One sentence explains “Approve adds the other photo to your tray. You delete later, with Apple's confirmation.” Display a short labeled practice using synthetic demo images without requesting Photos access. Practice cannot write to the real tray.
2. Show three choices: Keep left, Keep both, Keep right. A single practice choice demonstrates the matching Keep/Delete marks and Undo. Practice is optional and replayable from Help; never gate all returning users behind it.
3. Ask for library access only when the user chooses to find their photos. Reuse permission priming; denied/restricted states have a useful explanation and available Settings route; limited access works without pressure to grant full access.
4. If results already exist, present the first eligible pair immediately. Otherwise show existing scan progress and progressive results; do not silently start a huge scan from a tab visit. “Check recent 100” is offered only after F04 implements real scoped inventory. Until then, show the actual supported scan action and explain its coverage.
5. First real pair includes a compact directional hint. The first horizontal choice displays a plain Approve label and tray explanation. After approval, toast “Added 1 photo to your tray”; offer Undo. Do not describe this as deleted or space freed.
6. Session end: “Reviewed 12 pairs · 5 photos ready in your tray”; primary Review tray, secondary Done for now. Keep both and Skip are valid outcomes. An empty feed explains whether more scanning, limited access, unavailable thumbnails or no eligible pairs caused it; never “Your library is clean.”

First-value success is observed through local tests and owner usability sessions, not analytics. Measure time from available seeded results to a correctly understood first choice, number of taps and mistaken-direction attempts; establish device targets after measurement. No “saves five minutes” or accuracy claim without evidence.

## Pair model, provenance and eligibility

Introduce a pure pair/session value with stable identity, left/right IDs, member revisions, parent group ID, relation/provenance, evidence version and explicit decision. App adapters attach snapshots and verified bytes. Suggested conceptual provenance cases: full-resource exact; Vision-compared similar; same-burst review; time/hash review. Only the first two belong in a feed labeled “matching or closely similar.” Burst/time proximity alone must not be presented as proof of close similarity.

Current `PhotoReviewGroup.evidence` does not record how a `.visuallySimilar` edge was obtained. `ScanEngine` creates all-pairs similar edges for sequence groups without a Vision comparison of each edge. The `near-*`/`seq-*` ID prefix is a practical V1 discriminator, not a durable domain schema. Add typed provenance before expanding pair generation; decoding old cached groups yields unknown provenance and those groups stay in ordinary group review.

Initial bounded feed rules:

- Exactly two distinct still-image members, live group identity and nonempty revisions; supported direct evidence between the two.
- Exclude reviewed groups, rechecking groups and every photo involved as keeper or target in group/standalone tray entries, including entries needing attention.
- Deduplicate pairs by unordered member IDs and revisions. Resolve cross-category/group overlap deterministically so one session cannot contradict another approval. Recheck conflicts at approval, not only feed construction.
- Preserve parent group identity for a whole two-member group, so inbox, reviewed state, tray and revalidation agree.
- Unknown/unavailable thumbnails do not permit blind comparison. Keep both/Skip can remain available; selection requires both review images to have been displayed or an explicit ordinary-review fallback.
- Protected sides remain visible and marked with the reason. A choice that would remove a protected side is blocked; a choice that keeps it can be valid. If neither side can be removed, use Keep both/Skip or omit with an honest explanation.

Exact mode still requires a deliberate choice in this feature. Existing exact inbox preselection stays unchanged. If reusing `GroupReviewModel` initializes exact candidates as Delete, suppress the pair's Approve action until the user chooses and show the initial pair as undecided/suggested Keep, not a completed personal decision. Prefer an explicit initialization mode over duplicating policy. Once the choice is made, reorient the pair and use the existing exact verification path. If the former keeper lacks a verified-byte entry, obtain a known verified record size or show unknown; do not copy another photo's byte count without established provenance.

## Larger groups: explicit later phase

Do not split a three-photo group into independent tray entries that can delete one another's keepers, and do not mark the whole parent reviewed after deciding one pair. V1 excludes these groups.

Recommended expansion is a **parent review session**: pairs are a presentation of one group's draft, not independent approvals. Track all members as Keep/Delete/undecided, each explicit decision, each comparison edge, and parent revisions. Only visible photos can be marked by a pair action. Keep both marks those two Keep; unshown siblings remain undecided. A final parent summary shows all Keep/Delete/undecided members before one group approval; ending early can save an unapproved draft.

A simple winner tournament is rejected: A≈B and B≈C do not prove A≈C. Before a final removal, require direct admissible evidence from that target to a surviving keeper, using the existing Core policy; presentation proximity or a chain of wins is insufficient. If a previously retained keeper is later selected for removal, recompute dependencies and unmark affected deletions or require renewed comparison. Every target must have been explicitly shown and chosen. Preserve multiple keepers and protected items.

Show “Pair 2 · 6 photos in this group” and “Review whole group.” Do not claim pair count equals independent evaluation opportunities. Group-level review completion and tray state update atomically only on parent approval. Add no broader similarity threshold merely to fill the deck.

## Decision state and interactions

State machine: loading → ready → choosing → chosen → approving → advanced; warning/checking/stale/error are explicit substates. Keep both transitions ready/chosen → advanced after clearing staged deletion. Cancelled or below-threshold gestures return to the prior stable state. A pending confirmation, recheck, delete, missing image or stale generation blocks dependent actions.

Gesture requirements:

- Horizontal movement previews the keeper direction before release; overlay both text and icon (“Keep left,” “Other photo: Delete”). The deck does not hide either image during comparison.
- Recognition threshold and axis dominance are named design tokens. Tune on device; a short flick or vertical list scroll must not accidentally choose. Only commit at gesture end after direction is unambiguous.
- Up means Keep both, not approve. Down is neutral/scroll or cancels a staged choice; never assigns an undocumented deletion meaning.
- While zoomed, pan/zoom owns the gesture. Buttons and Compare remain reachable. Respect system back gestures at screen edges.
- Freeze the pair identity during an active drag; scan results can extend the queue but cannot move a new photo underneath the finger. On release, compare captured generation to the current pair; discard stale input.
- Rapid gestures/key repeats are coalesced or ignored until the current state transition completes. Do not allow a held key to process a new pair automatically.
- Reduce Motion uses a short cross-fade; no decorative looping motion. Model-owned haptics fire once per semantic event, and visible/spoken feedback works without them.

Buttons: Keep left / Keep both / Keep right, Compare, Approve after a valid choice, Undo, Skip for now, Done for now, Tray. At AX sizes stack content without changing logical Left/Right labels. Suggested keeper can be labeled, but should not always occupy the same side if collecting preference labels; stable randomized side assignment belongs only to the optional calibration phase, never swaps mid-review.

## Safety mapping and race handling

`GroupReviewModel` currently derives blocked reasons and warning analysis for original candidates. For either directional choice, build an orientation-specific group with the chosen keeper and other photo as candidate, retaining original ID, snapshots and direct evidence. This ensures deleting the original suggested keeper gets exactly the same protection/warning checks. Alternatively generalize the shared model with tests; do not modify the draft alone and assume checks become symmetric.

Before approval: resolve the original group again, compare identity/members/revisions/flags/evidence, confirm still authorized, not rechecking/deleting, no tray overlap, valid displayed images, and warning analysis completed. Similar warning/unavailable-analysis acknowledgment is per loser, pair revision and evidence generation. Changing choice or pair invalidates inappropriate acknowledgment. Recheck after asynchronous work and before inserting the entry.

Approval uses existing `GroupReviewModel.approve`/`DeletionTray.approve`, recording `manuallyReviewedIDs` for the explicit similar loser and actual `keeperIDs`. Exact pairs still use exact evidence. Keep both/Skip never adds an approved plan. The final deletion remains `DeletionTray.deleteAll` → `PhotoDeletionCoordinator.commitBatch` → fresh snapshots → `SafetyPolicy.validateBatch`/standalone policy → exact rehash → fresh checks again → the one `PhotoKitLibraryClient.delete` call → Apple prompt → reconciliation.

No change to SafetyPolicy, preservation flags, album protection, maximum 500 targets per batch, limited-access accounting or ML preselection. Known distinct/unique-content evidence remains a hard policy block; acknowledging a heuristic face/text warning cannot override it. Unknown originals are never “verified exact.” An interrupted/cancelled check is not an approval.

Undo must restore the preceding pair and its valid choice and remove exactly the tray entry added by that action. Do not restore a full old tray snapshot over unrelated changes. A revision conflict returns to fresh review. If the user has already deleted through the tray, app Undo cannot restore a PhotoKit deletion; offer the existing Recently Deleted explanation. Multiple pending sessions require group reservations or shared conflict checks before expansion.

## Resumability, storage and privacy

Persist unapproved pair/group drafts separately from tray approvals, keyed by member IDs, revisions, provenance version and source group. Save on meaningful decision changes and scene background, not every drag frame. On load, check decoding version and current group; corrupted/missing state falls back to fresh review. Store only intent and bounded history, no photos, OCR text or face data. Preserve file protection and backup exclusion.

Keep both/Skip review markers should be revision-scoped so edited photos may legitimately return; current `reviewedGroupIDs` alone is insufficient to implement that promise. Any persistence migration must preserve existing approvals and be tested from old tray/store fixtures. Decide whether ordinary inbox and swipe share one reviewed marker (recommended for a whole original pair); subset decisions use the separate parent draft.

Bound undo history (existing review limit 20 is a suitable starting point) and prefetch the current plus at most a few next pairs. Recompute feed on actual group/tray changes, not body evaluation or each progress tick. Cancel obsolete thumbnail/analysis tasks; stale completions cannot enable a different pair. Do not store raw IDs in diagnostics. Sharing labels/diagnostics remains explicit user action.

## Optional local calibration

Two separate controls, both off by default: **Learn my keeper preferences** and **Show only closer matches**. Explain the difference. The first affects suggested keeper/order; the second narrows which similar pairs are offered. Neither marks photos Delete, approves, changes hard protections, or modifies final policy.

### Keeper preference learning

Use explicit, completed keeper choices as preference observations only after opt-in. Exclude all exact-pair choices, protected/forced choices, skipped/both choices, unavailable comparisons, tutorial/demo actions and undone actions from pairwise winner labels. Identical-photo choices can reflect metadata or attachment rather than aesthetics. Keep both can mean meaningful difference, attachment or uncertainty; it is not evidence that either photo is better or that the detector made a false match. Optional reason buttons can distinguish “Better photo” from “Other reason”; absence of a reason must not be invented. Do not infer sensitive traits or learn from recognized faces/text identities.

Treat screen side and displayed suggestions as confounders. Record whether a suggestion was visible, evaluate left/right bias locally, and collect optional calibration examples with balanced stable side assignment and no suggested-keeper badge. Never change sides after the person starts reviewing. Exclude tutorial observations entirely. Report agreement separately on unbiased held-out choices; do not call agreement with a prominently displayed suggestion learned preference.

Store bounded feature differences already supported by `QualitySignals`, label, model version and an install-local anonymous group token for independent splitting; no photos/OCR text/location/date-of-photo. Tokens and examples stay local, excluded from backup and erasable. Retention default proposal: at most 500 explicit observations, rolling 90 days; both are product defaults to validate, not existing behavior. Training is cancellable, off-main and only when idle; failure keeps v1.

Start with an explainable preference setting (“Favor sharpness” / “Balanced”) before enabling learned weights. For automatic local fitting, retain v1 until there are enough independent held-out groups to compare and predeclare a minimum improvement criterion. Use the repository's ≥5 percentage-point held-out top-1 agreement requirement as the conservative default; proposed minimum sample count 100 independent usable groups is a feasibility threshold, not statistical proof of safety. Sparse/tied/unstable results keep v1. Keep bursts from one event in the same split and avoid training/test leakage. Cap weight changes, normalize inputs, reject NaN/out-of-range data, and version all models. A UI “Learning” indicator reports observations, not fabricated confidence.

The user can pause learning, inspect what the setting changes, reset learned data and return to v1 without clearing photos or the tray. Turning learning off stops collection and fitting; provide a separate explicit “Delete learned preferences” action. Model drift/change never invalidates an approval's original safety evidence or silently changes a current pair.

### Clustering conservatism

Prefer an explicit “Closer matches only” filter. It can lower the existing similar-distance acceptance threshold or hide uncertain-provenance pairs; it cannot raise the threshold above the currently reviewed baseline or synthesize missing direct links. Existing <0.32 Vision distance is an uncalibrated retrieval threshold, not “68% similar.” A future local calibrator can suggest a narrower filter after optional “These are too different” feedback. Keep both alone is ambiguous and must not train it.

Changing the filter rebuilds future feed eligibility, preserves the current stable pair until an explicit transition, and never reclassifies existing tray entries as exact. If suggestions become sparse, explain why and allow returning to the baseline; never relax conservatism silently to meet a daily quota.

### ML_GATE boundary

`docs/ML_GATE.md` stays OFF for non-identical automatic preselection. Local swipe preferences cannot satisfy its held-out population and independent-safety requirements. The gate requires a harmful-suggestion upper bound below 0.1% at 95% confidence, at least 2,995 independent zero-failure opportunities for that special case, population coverage and a signed-off code change. A single user's 100 or 500 preferences neither proves redundancy nor authorizes preselection. Even a future gate change would not authorize automatic deletion. This plan requests no safety-gate change.

## Phases, file map and exits

| Phase | Work and files | Acceptance / scope boundary |
|---|---|---|
| S0: minimal V1 | `SwipePairModel`, new swipe view/tab shell, `CleanSlateApp`, synthetic pair fixtures/tests; reuse GroupReviewModel/tray | Two-member similar groups only if that is the shipped implementation; both directions protected; explicit approval; no device claim |
| S1: full requested pair contract | Extend pair model with exact mode, typed provenance, up gesture, button parity and exact initialization mode; `PhotoModels`, `ScanEngine` adapters only as required | Exact + close-similar coverage; zero similar preselection; exact final rehash unchanged; unknown provenance excluded |
| S2: first value and polish | New practice/help components, empty/progress states, Compare, evidence/warning presentation; integrate F04 scoped entry when available | Demo cannot affect real tray; permission denial/limited flows; first choice understood; accessibility/light/dark/AX3 |
| S3: durable sessions | Pure Core draft/session type, app persistence adapter, bounded undo, group/tray invalidation integration | Leave/relaunch/resize/scan changes preserve only valid intent; migration round-trip and corrupt-state tests |
| S4: larger group review | Parent draft and pair scheduler, final summary, direct-edge/dependency checks, group-level approval | Hidden siblings untouched; no transitive deletion; multiple keepers; all group members accounted for |
| S5: explicit preferences | Optional local settings and closer-only filter; no learning yet | Defaults unchanged; filter only narrows; no policy/config gate changes; reset reliable |
| S6: experimental local fitting | Pure fitting adapter around KeeperRanker/RankerFitter, local observation store, privacy inventory integration | Independent held-out improvement; bounded resource use; off/reset/undo respected; no deletion or preselection effects |
| S7: device experience / iPad | iPad adaptive/input integration per separate plan; owner usability/device checks | Devices validate gestures, image quality, warnings, performance and actual system prompts |

Prefer new focused models over growing existing SwiftUI views past 300 lines. Keep gesture interpretation and decision transitions testable in Core; PhotoKit/Vision/UIImage stay App-only. Do not run policy validation from a new unauthorized call site that bypasses `check_policy_separation.sh`; reuse supported approval/coordinator seams. Existing safety tests are append-only.

## Test matrix and acceptance gates

Core/state tests: left/right/both exact mapping; short/diagonal gesture cancellation; stable pair identity; unknown/duplicate members; at least one keeper; parent hidden siblings; direct-edge dependencies; revision-scoped review markers; bounded undo; corrupt persistence; preference constraints and nonfinite fitting data.

Fake-library integration:

1. Both orientations, exact and similar: one selected loser, correct keeper, manual review on similar; no library delete until tray confirmation.
2. Every hard and conditional preservation flag on either side; protected suggested keeper cannot become a deletable loser. Unknown/distinct/unique evidence never becomes an approved removal.
3. Warning pending, unavailable analysis, acknowledged warning, reverse choice, stale async completion: no silent authorization transfer.
4. Changed revisions, unchanged-revision changed flags, vanished keeper, permission revoke, recheck in progress, duplicate input and concurrent tray mutation all fail closed.
5. Pair overlapping exact/similar/standalone tray entries, same photos with swapped IDs/order, reviewed parents and larger groups are handled deterministically.
6. Keep both after a staged deletion clears it, marks the correct whole pair reviewed, and Undo restores only that action. Relaunch retains approvals but requires fresh draft/warning checks.
7. Exact choice deleting the former keeper still rehashes kept and deleted resource sets; changed bytes/cancelled Apple prompt preserve existing safety behavior. Limited-access absence remains uncertain.
8. No arbitrary scan starts on tab visit; partial results appear progressively; unknown images prevent blind marking; canceled requests cannot update the next pair.
9. Calibration off collects nothing; undo removes label eligibility; exact/forced/both choices excluded; group-split leakage test; model changes never alter `preselected`, `selectedIDs` or commit policy.

UI tests: real horizontal/up gestures plus button equivalents; direction labels and visual marks agree; center Keep both; Approve disabled initially; tray count/Undo; warning sheets; Compare and zoom-pan conflicts; denied/limited/empty/scanning/stale states; tab switch and resume; light/dark/AX3 screenshots; AX5 reflow; accessibility audit and named actions; Reduce Motion retains feedback.

Performance: bounded queue/image cache, no additional scan concurrency, no per-frame persistence or policy work, no main-thread Vision loop. Test hundreds of pair transitions and three scan/review sessions under the existing memory budgets. Measure device responsiveness/thumbnail latency before committing to a numeric product promise.

Each phase needs focused tests, `make core-test`, lint/policy separation, build and relevant iOS suites; feature closure uses full CI and budget runs, validator then gatekeeper. Log exact skips, failures and test environment. Owner physical-device checks use disposable libraries; pending F02/F03 and historical safety/device gates remain pending. No push, release or real-library deletion is implied by this plan.

## Verified APIs and decisions

2026-11-11 local SDK verification uses the same iPhoneSimulator27.2 SDK paths documented in IPAD_APP_PLAN.md. SwiftUI public declarations checked: `DragGesture` (:4787), `MagnifyGesture` (:12326), `accessibilityAction(named:)` (:253–286), `onKeyPress` (:25324–25336, iOS 17+) and `keyboardShortcut` (:26973). PhotoKit read-write authorization and limited-library picker headers were also checked. Existing thumbnails and warning/commit services should be reused; no new Apple API is required for minimal V1.

Default recommendations: separate Approve after directional choice; exact + verified close-similar whole pairs first; larger groups later with parent summary; practice optional; no daily quota; learning off; closer-only filtering; one shared tray; no new dependencies. Proposed gesture thresholds, local retention/sample counts, exact empty-state copy and layout breakpoints need prototype/device evidence. These are ordinary implementation choices within the feature, not permission gates. Owner approval remains necessary only for existing human-gated changes and release/device actions.
