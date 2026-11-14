# Engineering handoff — 2026-11-12

## Night shift 2026-11-13 — read this first

N05 is MERGED to main (9bbbead, PR #2). Main is green: Core 171, unit 452/0 failures, UI 75/0 failures (iPhone 17 sim). Work tonight on these branches, one at a time, in this order. Each already contains main and builds.

1. `feature/F05-progress` — spec `docs/features/F05-progress-experience.md`. INCOMPLETE: these tests fail and must pass:
   - `CleanSlateTests/EtaEstimatorTests/testEtaEstimatorStable` (XCTAssertNotNil at line 22, then a force-unwrap crash at line 23 — never force-unwrap in tests);
   - `CleanSlateUITests/ScanProgressUITests` (all 4 tests);
   - regressions this branch caused (they PASS on main): `CleanSlateUITests/ActivityStartUITests/testOverviewDoesNotScanAndRangePickerContainsOnlyBoundedChoices` and `CleanSlateUITests/ReviewFlowUITests/testAccessibilityAuditOnHomeAndReview` ("Contrast nearly passed").
2. `feature/F06A-trust-screens` — spec `docs/features/F06-first-run-trust.md`, ONLY the Privacy / Data on this iPhone (read-only, NO "Forget everything") / How deleting works / How to get photos back screens + menu items + Receipt/History links. INCOMPLETE: the required tests do not exist yet. Write `UITests/TrustUITests.swift` and `iOSTests/LocalDataInventoryTests.swift` from the spec's acceptance criteria and test plan, run them, fix the code until green. Reference only: branch `nightshift/F06-attempt-2` is an earlier divergent attempt — you may copy ideas from its tests, but they were wrongly placed in `Core/Tests` (Core cannot see App types; App tests belong in `iOSTests`), and it contains the forbidden preview gate. Do not merge that branch. Do NOT add the preview gate, forgetEverything, or onboarding changes.
3. `feature/IP4-ipad-input` (create NEW from main; any older branch of that name was renamed) — `docs/plans/IPAD_APP_PLAN.md` row IP4 + sections "Touch, keyboard, pointer and accessibility" and "Window lifecycle and state"; history in `docs/plans/IPAD_IMPLEMENTATION_LOG.md`. Scope: tap a queue row to open that group; keyboard shortcuts that each have a visible button; drafts kept when switching sections. Test on "iPad Pro 11-inch (M5)".

Small warm-up (on main via a branch `fix/n05-voiceover-flag`): `App/Views/SwipeSaveView.swift` around line 127 adds a "Never suggest" accessibilityAction even when `FeatureFlags.protectionRulesUI` is off — only add it when the flag is on; add a test.

Rules: never edit `docs/VALIDATION_LOG.md` except by APPENDING a new section at the end; never delete or rewrite earlier text in any doc. Never commit to main; push only your branch. Report exact test counts.


## Latest implementation — permission-free protection example

N05 first-session demo is implemented on the existing feature branch. On onboarding's first page, choose **Try protecting a sample**. This opens an explicitly labeled birthday illustration: Protect removes its simulated suggestion, Try again resets it, and dismiss/reopen starts fresh. It owns local view state only; no Photos/service/store/tray access. The existing three onboarding pages remain; their content now scrolls at large text sizes. The entry follows the existing protection creation-UI flag (Debug on / Release off). For an existing development install, launch Debug with `-resetOnboarding` to revisit onboarding.

Four focused tests pass on phone and four on iPad, including AX5 interaction and flag-off/onboarding completion. Core171, lint and unsigned device build pass; independent limited-increment review approved. Full integrated regression is running and will be recorded separately. AX5 reachability is not a VoiceOver/audit pass; fake authorization does not measure request counts. Remaining N05/owner/device/native iPad navigation gates below are unchanged.

## Current continuation — N05 (2026-11-12)

Draft review: [GitHub PR #2](https://github.com/rishiehari/cleanslate/pull/2). Code is on the feature branch; main receives documentation only.

The V2 package **is present**, at `docs/CleanSlate_Implementation_Specs_V2` (import f694156). Resume `feature/N05-protection-rules`; use `git worktree list` to find its checkout. Main remains the previously validated 9037790 baseline. Claude completed C1–C9 through 410b924, including phone, Swipe and iPad UI. Continuation code ba80f92 (canonical dates) and 5196133 (presentation/performance) is committed/pushed to origin. The older checkpoint/feature-status text below is historical and does not describe this branch.

This continuation fixes canonical Gregorian date conversion, captured rule-zone consistency, actual-width inspector eligibility, selection/search continuity, repeated presentation-metadata reads and AX5 presentation. See [N05 review packet](plans/N05_REVIEW_PACKET.md) for scope, exclusions, safety review paths and residual limitations. The creation UI is enabled in Debug and disabled in Release; existing saved rules are enforced regardless of that flag.

**Do not merge N05 into main yet.** Owner review of C1/C4/C5 is explicitly required by [the N05 plan](plans/N05_IMPLEMENTATION_PLAN.md). The default-size iPad ProtectSheet audit failure was corrected by native page sizing on both tested runtimes; no new audit exemption was added. A full final integrated CI run and native iPad sidebar-return automation remain pending; exploratory return checks failed and are not passing evidence. Full feature acceptance, album-rule UI, physical keyboard/pointer, limited-access device checks and release gates remain open. Do not start N04 until the recorded N05 gates are resolved. Current measured results are in the latest VALIDATION_LOG entry; do not treat an earlier compile-only or zero-test success as current product validation.

Test with synthetic libraries only. The owner-provided `CleanSlate-RealLib` simulator was not accessed in this continuation; its earlier authorization is not standing permission to inspect personal media. Metadata caching fixes repeated synchronous snapshot reads but cannot interrupt a single stalled PhotoKit call; physical-device latency remains unverified.

## Checkpoint and owner intent

Code checkpoint: `df429a3` on `main`, pushed to `origin/main`. It integrates the previously dirty parallel-agent work and restores a buildable app. Subsequent documentation commits may follow this SHA. Confirm current HEAD and working-tree status before editing.

The owner explicitly requested session closure and a buildable product for phone testing. No work is running on new premium-parity features. Any coding tool/agent can resume from these repository documents; no prior chat, process, agent ID or model is required. Coordinate file ownership if more than one tool is active. Keep feature implementation serialized.

Standing authorization: commit and push completed, validated increments without repeatedly asking (root AGENTS.md). Owner-requested checkpoint publication is distinct from claiming CI or release approval. Never force-push or publish credentials/photos. Device/release gates remain separate.

## Read in order

1. Root AGENTS.md, this file, current section of PROGRESS.md.
2. Last entries in VALIDATION_LOG.md and PHONE_TESTING.md.
3. PRODUCT.md, ARCHITECTURE.md and RELEASE_CHECKLIST.md.
4. plans/PREMIUM_PARITY_IMPLEMENTATION_ORDER.md and the next feature's specification.

Older dated entries and the large-library proposal documents contain historical/unverified claims; the current summary/evidence supersede them.

## Implemented behavior

- Metadata-first Home overview: dates/burst membership among up to 5,000 recent accessible items; ranked weeks, no image work, trip inference, location/face identity, downloads or estimated savings. One suggested week initially, more on expansion.
- Product scan default: past month, newest first, hard cap 2,000. Past two months, suggested weeks and latest 100/1,000/2,000 supported. Album scope and a cursor that advances to unseen older batches are NOT implemented/offered.
- PhotoInventoryReader owns serial off-main metadata reads, public PhotoKit date predicates/fetch limits, 25-item pages and deadline/cancellation. An already executing synchronous PhotoKit call cannot be forcibly killed; the UI returns and additional cancelled-page work is suppressed.
- Each bounded scan rebuilds active index membership; earlier wide cached inventories cannot bypass the cap. Out-of-scope index rows do not establish Photos deletion. Receipt/tray schema preserved.
- One shared scan task/cancellation owner, progress banner, tray and receipt presenter. No new mutation/deletion path, SafetyPolicy weakening, concurrent scan workers or automatic original download.
- Shared phone/tablet features; sidebar-adaptive tabs, responsive standalone grid, equal Compare panes and contextual queue where geometry permits. Queue is read-only; direct queue selection/cross-destination draft restoration/full keyboard work remain open in the iPad plan.
- Hosted unit-test app environments use a fake library. PhotoKit observation waits for authorization.

## Validation: what passed

- Final generic simulator build via `make build`.
- Final physical-device arm64 compilation via `xcodebuild -project CleanSlate.xcodeproj -scheme CleanSlate -derivedDataPath build/DeviceDerivedData -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`. Unsigned: not installed/tested on a phone.
- Core: 118 tests. Fixtures: 7. Synthetic eval gate. Lint/policy separation and whitespace checks.
- Clean broad iOS unit rerun: 309 tests, 2 simulator skips, 0 failures; excludes memory and F03 watchdog, run separately.
- Focused scoped/Swipe/watchdog run: 25 tests pass; 10k-photo no-main-block watchdog passed after CPU quality work moved off main.
- Pinned tier-M memory run: 2 tests pass. 10k peak 47 MB against 160 MB budget; 6.7 MB marginal settled growth; released three-run soak 33.1/33.1/33.1 MB. Simulator tier pinning is not physical-device evidence.
- Phone scoped/background/overview/iCloud opt-in and behavioral Swipe checks pass. iPad overview/Compare/queue rotation checks pass; queue test collapses the system sidebar to supply sufficient detail width.

## Known failures — status (updated 2026-11-12, Claude Code session)

The two audit failures above are CLOSED (Swipe hit region; Home contrast via a geometry-bound chrome-zone exemption with re-audit). A full integrated `xcodebuild test` is green (see VALIDATION_LOG 2026-11-12 "Real-library simulator stability fixes"). Three crash/function defects that only real PhotoKit exposes were fixed (Swift 6 isolation traps incl. the delete change block, fastFormat thumbnail 3303, BGTask submit without registration), plus a pre-existing cross-chunk deletion-safety bug (Core `TrayConsistency`).

Still open: AX5 Swipe audit (no test), physical-device gates, ~2 s launch main-thread block on simulator, and the owner decision on Swipe n Save's empty feed on real libraries (`seq-` sets vs `near-` pairs).

Real-library simulator testing: `CleanSlate-RealLib` simulator holds an owner-provided copy of recent photos for local text-metric testing only. Never view, upload or log its images/screenshots/metadata. Run `TEST_RUNNER_CLEANSLATE_REALLIB=1 xcodebuild … -destination 'platform=iOS Simulator,name=CleanSlate-RealLib' test -only-testing:CleanSlateUITests/RealLibrarySmokeUITests` (add `TEST_RUNNER_CLEANSLATE_REALLIB_ALLOW_DELETE=1` only for the one-copy deletion test).

N05 (protection rules) is being implemented on branch `feature/N05-protection-rules` (planner → executor → validator rounds). It changes the deletion coordinator and adds a hard preservation flag, so it is NOT merged to main until the owner reviews the safety diff (AGENTS.md: push authorization excludes safety-policy changes). Plan: docs/plans/N05_IMPLEMENTATION_PLAN.md.

## Reproduce and collect evidence

Run `make gen`, `make core-test`, `make fixtures-test`, `make eval`, `make lint`, `make build`. Focus UI work on iPhone 17 Pro (iOS 26.5) and iPad Pro 11-inch (iOS 27.2) available in this session; re-list installed devices instead of assuming their IDs remain valid. The iPad mini initially hung during first boot; use a healthy simulator and report environment failures honestly.

Targeted xcodebuild tests use `-only-testing:CleanSlateTests/ScopedScanTests`, `-only-testing:CleanSlateTests/F03AcceptanceTests`, `-only-testing:CleanSlateUITests/ActivityStartUITests`, `-only-testing:CleanSlateUITests/ReviewFlowUITests/testAccessibilityAuditOnHomeAndReview`, and `-only-testing:CleanSlateUITests/SwipeSaveUITests`. Existing UI fake mode is `-uiTestingFakeLibrary -skipOnboarding`; add `-uiTestingSwipe` for the swipe fixture. Never use personal media in agent testing.

Prior session logs remain locally at `/tmp/cleanslate-*.log`; result bundles are under ignored build/DerivedData, build/IPadDerivedData and build/DeviceDerivedData. These are ephemeral aids, not portable evidence; key results/failures are recorded in VALIDATION_LOG.md.

## Device test / next features

Owner signing and run instructions: PHONE_TESTING.md. Device PhotoKit latency, real cancellation, limited-access changes, Apple prompts, Vision, Instruments and iPad windowing remain unverified. No release/TestFlight approval.

Historical sequence: N05 → N04 → N07 → N06 → N01 → N02 → N03 → N08 → N09 → N10. The V2 package is now checked in, and N05 is implemented on its review branch as described at the top of this file; other premium-parity features have not started. Follow the per-feature acceptance/test/review process in the implementation-order document and update these handoff documents after each increment.
