# Validation log

Append one entry per step using the template in `docs/EXECUTION_PLAN.md` §0.3.

## Step 1 — Green CI, testable architecture, first device run — 2026-11-05
Start commit: 1891668  End commit: see `git log` (Step 1.x commits)

**make ci: PASS locally** — core 30 tests, fixtures 2, iOS 18 tests (1 skipped: Vision feature print needs device hardware; ran 14 new coordinator tests).
GitHub Actions run: NOT VERIFIED (no push performed; the plan says not to push without the human). Workflow now uses `make` targets, `macos-15`, newest installed Xcode, and uploads logs on failure.

### Findings
- Root cause of the red simulator test: Vision feature prints throw `Failed to create espresso context` on the iOS 26.5 simulator (no inference context). The old API turned that into `nil`. Fixed by migrating to the Swift Vision API (`async throws`) and skipping on the simulator with the real error text; the same test FAILS on a device.
- Consequence: Vision-based similar-photo matching can only be exercised on a physical device. The simulator covers exact matching, dHash, UI and fakes.
- The Swift Vision API is `GenerateImageFeaturePrintRequest().perform(on: CGImage, orientation:)`, async, checked against the iOS 26.5 SDK swiftinterface.

### Guard-by-guard comparison: `PhotoDeletionCoordinator.commit`, before vs after the refactor
| # | Guard | Before | After |
|---|---|---|---|
| 1 | single commit at a time (`.busy`) | yes | yes |
| 2 | non-empty selection | yes | yes |
| 3 | Photos access authorized/limited | yes | yes |
| 4 | fresh snapshot (with albums) for every involved ID, else `.vanished` | yes | yes |
| 5 | `SafetyPolicy.validateCommit` on fresh records | yes | yes |
| 6 | exact groups: rehash keeper + every target, signatures must match | yes | yes |
| 7 | after hashing: revision unchanged AND no protection flags (except keeper) | yes | yes (one snapshot instead of two) |
| 8 | access re-checked right before deleting | yes | yes |
| 9 | every selected ID resolvable at delete time | `deletables.count` check | `PhotoKitLibraryClient.delete` throws `notAccessible`, mapped to `.vanished` |
| 10 | removal reconciled only with `.authorized` access | yes | yes |

### Tests
- 16 `DeletionCoordinatorTests` after review fixes (plan asked for 9): exact deletes only selected, stale revision, keeper vanished, bytes changed, original not local, favorited during hash, flag change without revision change, protected target blocked before hashing, user cancels system prompt, concurrent commit rejected, limited access never counts as verified, revoked access, empty/keeper selection, similar requires manual review.
- **Mutation check:** disabling guard 7 made 2 tests fail; disabling the signature comparison in guard 6 made 1 test fail. Guards are covered by tests that can fail.

### Self-review
- Existing SafetyPolicyTests changed: **no** (`git diff 1891668 -- Core` is empty).
- `deleteAssets` has exactly one call site: `PhotoKitLibraryClient.delete(ids:)`, reachable only from `PhotoDeletionCoordinator.commit` after guards 1-8.
- Network: only `isNetworkAccessAllowed = false` (two places). No `URLSession`.
- Main-thread work: unchanged from baseline (the scan still runs on the main actor; fixed in Step 5).
- Known behavior kept as-is: a failed post-hash revalidation reports `.vanished` ("no longer available") even if the cause is a changed revision/flag. Message improvement is a Step 6 item.

### /code-review (medium) on 1891668..HEAD — 9 findings, all addressed
| # | Finding | Outcome |
|---|---|---|
| 1 | Vision failures swallowed with `try?`, scan "succeeds" with zero similar groups | Fixed: `statistics.visionFailures` counted and shown in the scan status message |
| 2 | Change observer: single handler slot, `deinit` comment wrong, `stopObserving` dead | Fixed: `observeChanges` returns a `ChangeSubscription` token (multiple observers, unsubscribes on release); test added |
| 3 | `digests` errors not mapped to `DeletionError` | Fixed: new `.cannotVerify`; cancellation passes through; test now asserts the exact error |
| 4 | Window between final revalidation and the real delete | Partly disputed (the old code also refetched after revalidation) but hardened anyway: `delete(ids:expectedRevisions:)` re-reads the exact objects it deletes and aborts on any revision mismatch; test `testChangeAtTheLastMomentIsCaughtByTheDeleteCall` |
| 5 | Makefile `SIM_ID` eager + no guard | Fixed: lazy variable and an explicit "no simulator" error |
| 6 | CI could pick a beta Xcode | Fixed: betas filtered out |
| 7 | `mac-build`/`mac-tests` aliases misleading | Removed |
| 8 | Redundant sorting / ordering contract | Contract documented in the protocol |
| 9 | Digest stage swallowed cancellation | Fixed: cancellation now stops the scan |

### Human gate 1.7 — first physical device run: **PENDING (needs the owner)**
Checklist for the owner (disposable library, iCloud Photos OFF, ~30 photos incl. 3 pairs made with Photos "Duplicate"):
1. Install on iPhone with a personal-team signature; confirm the Photos permission prompt text.
2. Run `docs/DEVICE_TEST_PLAN.md` sections "Build and permissions" and "Deletion canary tests".
3. Confirm `VisualFeaturesTests.testFeaturePrintOnThisRuntime` PASSES on device (not skipped).
4. Report: any crash, any pair the app marked exact that was not byte-identical, and the Apple deletion prompt wording.
Work on Steps 2+ continues on simulator/fake data in the meantime; nothing in Step 2-2B depends on the device run.

Known gaps carried forward: GitHub Actions run unverified; device run pending; scan still on main actor; Swift 5 mode.

## Step 2 — Positioning, iOS 26, category IA, onboarding, UI test infrastructure — 2026-11-05
**make ci: PASS** — core 30, fixtures 2, iOS unit 20 (1 simulator skip), UI 4.

- `docs/PRODUCT.md` written (positioning vs Apple's Duplicates album, categories, non-goals, metrics).
- **iOS 26 minimum adopted** (`project.yml`). Core package keeps its lower platform floor (no iOS 26 APIs inside Core). *Default recommendation adopted by the agent while the owner is unavailable; **owner confirmation PENDING**; reversible.*
- Home restructured into category cards (`ScanCategory`, `CategoryCardView`, `CategoryGroupsView`). Unbuilt categories show "Coming in a later build" and only in DEBUG.
- 3-screen onboarding (privacy / how deletion works / Apple's Duplicates album tip). Stored in `UserDefaults` key `onboarding.seen.v1` (privacy manifest entry due in Step 10.2).
- UI test target `CleanSlateUITests` with DEBUG-only launch modes: `-uiTestingFakeLibrary`, `-uiTestingAuth denied|limited|...`, `-resetOnboarding`, `-skipOnboarding`. `FakePhotoLibrary` moved to `App/Debug/` (compiled in DEBUG only; renders deterministic scene thumbnails).
- UI tests: onboarding shown then dashboard, category cards render, a category opens its group list, denied permission shows the permission card.
- Two test-infrastructure lessons recorded: (1) a container's `accessibilityIdentifier` overrides its children's unless `.accessibilityElement(children: .contain)`; (2) `-key value` launch args live in UserDefaults' argument domain and **cannot be overwritten by the app**, so onboarding reset/skip uses real writes.
- Screenshots: `docs/screens/step2/` (onboarding, dashboard, permission-denied; default iPhone 17 Pro simulator).

Review: no SafetyPolicy/Core change. Delete path unchanged (grep: single `deleteAssets`). UI is intentionally plain; visual design is Step 2B.
Human gate: owner to confirm PRODUCT.md and the iOS 26 decision. **PENDING**.
Known gaps carried forward: Home still shows engine-flavored text ("0 inventoried"), to be redesigned in 2B.
