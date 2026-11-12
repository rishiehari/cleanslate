# Engineering handoff — 2026-11-12

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

## Known failures — do these next

The initial full `make ios-test` completed with failures. Subsequent focused runs fixed functional/model/fixture/watchdog failures, but there is NO fully green final integrated CI claim.

1. `ReviewFlowUITests.testAccessibilityAuditOnHomeAndReview`: contrast sampling still flags text near the floating-tab/occluded scroll edge. Failing text moved as layout changed; last observed label was “What to review.” Bottom-edge fade was disabled and content made readable, but the audit has not passed. Verify actual visible geometry/screenshots; do not silently whitelist/remove assertions.
2. `SwipeSaveUITests.testSwipeAccessibilityAudit`: final closure run still fails hit-region audit on the photo image accessibility representation: `swipe.photo.sw1-left`, reported bounds about 19.7 × 15.3 pt. Named keep/compare actions are now on the review deck and visible buttons; investigate SwiftUI representation/action propagation and give interactive focus an actual 44-point minimum without losing photo labels/decision values or changing approval guards.
3. The separate AX3 Swipe audit passed in a prior final-source iteration. Re-run default/AX3/AX5 and behavior after fixing the representation; do not assume the full matrix passed.
4. Re-run full integrated CI and appropriate budgets after these fixes. Do not start N05 implementation while fixable current regressions remain.

Test execution rule: do not run two xcodebuild test sessions against the same simulator simultaneously. One attempted overlap interrupted a unit run; it was excluded from passing evidence and a clean run followed.

## Reproduce and collect evidence

Run `make gen`, `make core-test`, `make fixtures-test`, `make eval`, `make lint`, `make build`. Focus UI work on iPhone 17 Pro (iOS 26.5) and iPad Pro 11-inch (iOS 27.2) available in this session; re-list installed devices instead of assuming their IDs remain valid. The iPad mini initially hung during first boot; use a healthy simulator and report environment failures honestly.

Targeted xcodebuild tests use `-only-testing:CleanSlateTests/ScopedScanTests`, `-only-testing:CleanSlateTests/F03AcceptanceTests`, `-only-testing:CleanSlateUITests/ActivityStartUITests`, `-only-testing:CleanSlateUITests/ReviewFlowUITests/testAccessibilityAuditOnHomeAndReview`, and `-only-testing:CleanSlateUITests/SwipeSaveUITests`. Existing UI fake mode is `-uiTestingFakeLibrary -skipOnboarding`; add `-uiTestingSwipe` for the swipe fixture. Never use personal media in agent testing.

Prior session logs remain locally at `/tmp/cleanslate-*.log`; result bundles are under ignored build/DerivedData, build/IPadDerivedData and build/DeviceDerivedData. These are ephemeral aids, not portable evidence; key results/failures are recorded in VALIDATION_LOG.md.

## Device test / next features

Owner signing and run instructions: PHONE_TESTING.md. Device PhotoKit latency, real cancellation, limited-access changes, Apple prompts, Vision, Instruments and iPad windowing remain unverified. No release/TestFlight approval.

After current integration/device feedback: N05 → N04 → N07 → N06 → N01 → N02 → N03 → N08 → N09 → N10. The source research summary is checked in; its linked 24-file bundle was NOT supplied locally. N05-protected-rules.md is a specification only. No premium-parity feature has been implemented or enabled. Follow the per-feature acceptance/test/review process in the implementation-order document and update these handoff documents after each increment.
