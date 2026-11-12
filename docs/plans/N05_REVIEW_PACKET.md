# N05 protection rules — review packet

Review: [draft PR #2](https://github.com/rishiehari/cleanslate/pull/2).

Status: implementation branch; owner safety review and physical-device gates remain PENDING. Not merged into main. This packet describes the implemented increment, not full V2 feature completion.

## Scope and branch

Continue `feature/N05-protection-rules` (find its checkout with `git worktree list`). Claude implemented C1–C9 through 410b924, based on main 9037790. Continuation commits ba80f92 and 5196133 validate that work and fix calendar/time-zone, presentation-metadata performance and adaptive-presentation defects. Both are published to origin on the feature branch. No subsequent premium-parity feature has started.

In scope: per-photo and inclusive date-range rules; durable SQLite rule state/revision; fail-closed loading/loss/write handling; suggestion filtering; approval/commit protection; sticky tray invalidation; phone and iPad rule UI; Swipe entry points. Existing rules remain enforced when creation UI is disabled. Release creation UI remains OFF, Debug ON unless explicitly disabled.

Not implemented: album-rule creation/full-access membership UI, permission-free feature demo, feature impact counters, category/media-type exclusion rules. Album rule data is represented by the evaluator but unknown membership fails closed. Existing blanket curated-album protections are not weakened. Physical keyboard/pointer and Photos behavior are not established by simulator results.

## Safety diff requiring owner review

Review the main-to-feature diff in these areas before merge:

- Core Models/ProtectionRules and hard `userProtected` classification: protection is an evaluation-time overlay, never stored as native asset metadata. Existing hard/conditional policy assertions remain.
- ProtectionRuleService/ProtectionGate: one app-owned rule service, durable revision tracking, unavailable/lost store handling and pending-write behavior. Creation UI flag does not disable enforcement.
- LibraryStore migration 1 → 2: additive rule/revision tables; existing assets, fingerprints, digests and receipts preserved; reset preserves protection intent. Existing DB writer retained.
- PhotoDeletionCoordinator: fresh protection results on single/group/batch paths, including after asynchronous hashing and rule-revision changes. Still one PhotoKit delete API site.
- CleaningViewModel/DeletionTray/GroupReviewModel: guarded recommendations/approvals and persisted sticky tray invalidation; removing a rule cannot resurrect authority to delete.
- ProtectSheet/ProtectionRulesView/Swipe: explicit confirmation and rule removal; rule changes never themselves mutate Apple Photos.

Inspect the tests for mid-rehash protection changes, protected targets across >500-item trays, failed writes, missing/corrupt stores, old tray restoration, removing rules and feature-flag-off enforcement. Do not infer safety from UI screenshots.

## Continuation fixes

- Gregorian canonical-day extraction from DatePicker instants even when the user displays a Buddhist/non-Gregorian calendar; captured rule time zone used consistently for picker, count and write. Rule dates display in the stored zone. Added Core calendar/zone/DST regression tests.
- Inspector eligibility uses actual available width and accessibility text. The existing selected rule survives pushed-detail/inspector transitions. An active search remains editable after narrowing the window. Added layout and rotation/search tests.
- Presentation metadata is loaded once per distinct photo in a cancellable pass that yields every 25 reads, replacing quadratic whole-group dictionary reconstruction. Cancelled date-coverage tasks cannot publish stale counts. Individual PhotoKit snapshot calls remain synchronous on main; one stalled call cannot be interrupted.
- A native scope menu accommodates long accessibility labels. Photo switches have distinct spoken positions; a date-range save UI test asserts zero delete calls and an empty tray.
- Accessibility-sized rules rows put full-width labels first, then the thumbnail and existing removal button together; unavailable-photo copy is concise. The nested iPhone management destination hides floating tab chrome while active and restores main navigation on Back; bottom scroll-edge fading is suppressed. Protection explanation precedes the selection controls, uses explicit readable contrast, and avoids bottom-edge fading. Added AX5 sheet/rule-screen audits.

## Automated audit fixes and remaining gates

Default-size iPad ProtectSheet `testProtectSheetAccessibilityAudit` initially reported `elementDetection`: "Potentially inaccessible element", with no element and a zero frame, on both iOS26.5 and27.2. Native `.presentationSizing(.page)` corrected the measured audit on both runtimes; no exemption was added. AX3/AX5 and explicit save/cancel flows have separate checks. The background-OCR explanation is only a hypothesis; the audit result establishes behavior, not its internal cause.

The broad phone run exposed AX5 rule-row contrast/clipping. Accessibility-sized rows now put full-width labels before the thumbnail/removal-control row; the list disables bottom-edge fading and iPhone management hides floating tab chrome while active. Return navigation has a behavioral regression test. Final focused evidence is in VALIDATION_LOG. The earlier full invocation failed; it cannot be relabeled green after focused fixes.

An independent continuation-diff review found no correctness blocker in the calendar/cache/layout and stacked-row changes. It did not approve full N05 completion, main merge or release. Native iPad sidebar-return automation remains unresolved: exploratory checks could not activate the destination, and no return pass is claimed. The added tab-visibility test is iPhone-only, matching the platform receiving tab hiding; its iPad skip is not gate evidence. The owner/device gates remain independent.

## Residual boundaries

A protection rule created after PhotoKit's delete request has already been entered cannot retract Apple's in-flight system prompt. Older binaries do not implement user-rule enforcement; do not downgrade for rollback after creating rules. Keep the migration and enforcement layer when disabling creation UI. Date rules intentionally do not match missing creation dates. Limited-access album behavior needs separate device evidence.

## Validation and next action

Authoritative measured results and any unresolved failures are appended in VALIDATION_LOG.md and summarized in PROGRESS.md/HANDOFF.md. A zero-test xcodebuild success does not count. Do not merge to main or mark V2 N05 complete solely because the implemented subset passes automated tests. Finish current regression fixes, review this diff, and obtain the recorded owner safety review before merge; real-device release checks remain pending independently.

## Reproduce / resume

1. Fetch and enter `feature/N05-protection-rules` in its existing worktree; inspect current HEAD/status. Do not overwrite another worktree or personal-media simulator.
2. Run `make core-test fixtures-test eval lint build` (set `PY` to a virtualenv with fixture dependencies). Run a full `make ios-test SIM_ID=<synthetic-iPhone-ID>`; then the ProtectionIPadUITests and protection audits on a separate synthetic iPad. Never run simultaneous test sessions on one simulator. `make budget BUDGET_TIER=M` is a simulator-tier check, not a device gate.
3. Focused continuation tests: ProtectionCalendarConversionTests (Core), ProtectionSheetDatesTests / AdaptiveLayoutTests (CleanSlateTests), ProtectionUITests / ProtectionIPadUITests (CleanSlateUITests). Require nonzero executed-test counts. Deliberate Escape/real-library/hardware skips do not satisfy those gates.
4. Review C1/C4/C5 with the owner before main merge. Keep the single mutation site, fail-closed store behavior and protected-tray invalidation. Do not bypass this gate to begin N04.
5. Finish the explicitly deferred N05 scope and physical-device matrix; record each measured result in generic PROGRESS/VALIDATION/HANDOFF documents. Creation-UI rollback must keep migration and protection enforcement, because existing saved rules remain user intent.
