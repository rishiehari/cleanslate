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
