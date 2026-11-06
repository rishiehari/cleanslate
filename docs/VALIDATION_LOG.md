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

## Step 2B — Design system and Review → Approve → Tray → Delete — 2026-11-06
**make ci: PASS** — core 39, fixtures 2, lint (design-system rules, strict), iOS unit 20 (1 simulator skip), UI 14 (+3 screenshot captures skipped unless a capture dir is set).

### Built
- Tokens (`Spacing`, `Radius`, `IconSize`, role-named colors with light/dark in the asset catalog incl. `onAccent`), text styles (`appText`), SwiftLint design-system rules enforced in CI (`.swiftlint.yml`, only custom rules).
- Components: `PhotoTile`, `DecisionBadge`, `EvidenceChip`, `StorageHero`, `CategoryCardView`, `ApprovalBar` (Liquid Glass, one `GlassEffectContainer`, stacks at accessibility sizes), `TrayButton`, `UndoToast`, `ContentStateView`, `ConfirmSheet`, `HapticsService` (semantic events, user toggle).
- Core `ReviewDraft` (keep/delete marking rules U2–U4) with 9 tests including a 500-sequence property test.
- Flow: Home (hero, scan status, category cards, tray button) → inbox (progressive, "Approve all" with a reviewable list, reviewed filter) → `ReviewSessionView` (Approve/Skip opens the next group) → tray → confirm sheet → deletion → receipt. Compare view with shared zoom/pan. Tray persisted (excluded from backup).
- 5 prototype variants (DEBUG, `-prototype 1…5`), decision in `docs/design/PROTOTYPE.md`; word list; expert panel review `docs/design/PANEL_REVIEW_2B.md`.

### Evidence
- UI tests: approve moves to tray and never deletes (`deleteCalls=0`), similar opens with nothing marked, last Keep can't be removed, protected photo explains itself and blocks Approve, undo, approve-all then tray delete (keepers survive: 11 assets − 3 = 8), cancel in confirm sheet deletes nothing, tray survives relaunch, Approve opens next group, accessibility audit on Home and Review.
- Screenshots (light, dark, AX3): `docs/screens/step2b-v7/` (dark verified via `-forceColorScheme dark`; the simulator's own appearance switch does not take effect headless: even Apple's Settings stays white).
- Real defects found by looking at screenshots and fixed: identifier on a container hid child buttons; large text wrapped the approval bar over the photo (now stacks, clearance scales); contrast of badges/captions/buttons; confirm-sheet "Cancel" bleed-through (solid sheet background); toast wording ("Added N photos to your tray").
- Accessibility audit exemption (documented in the test): the contrast sampler cannot measure the two Liquid Glass buttons of the approval bar; verified by eye on light/dark/AX3 screenshots. All other elements remain audited.

### Self-review checklist
- Existing SafetyPolicy assertions changed: **no** (Core only gained `ReviewDraft`).
- `deleteAssets` call sites: still exactly one (`PhotoKitLibraryClient.delete`), reachable only through `PhotoDeletionCoordinator.commit`.
- Network: unchanged (two `isNetworkAccessAllowed = false`).
- **Interim behavior to fix in Step 8: the tray deletes group by group, so on a real device N groups = N Apple prompts. Do not run the tray against a real library with more than one group until Step 8 lands.**

### Deferred / carried forward
- Matched-geometry "fly into tray" animation (cross-fade + symbol bounce used instead; `ReceiptView` count-up is the only celebration).
- Next-group image prefetch (U6), Reduce Motion UI test, snapshot-testing dependency (needs owner approval; screenshot capture used instead), permission priming screen (the Home permission card explains why before the system prompt).
- **Human gates PENDING:** choose/confirm the review design (PROTOTYPE.md default adopted), 5-minute feel check on a real iPhone (fake-data mode `-uiTestingFakeLibrary` is DEBUG-only).

## Step 3 — Exact matching that works on real libraries — 2026-11-06
Start commit: 158d904  End commit: see `git log` ("Step 3" commits)
**make ci: PASS** — core 55 tests, iOS unit 32 (1 simulator skip), UI 16 (+3 screenshot captures skipped), lint strict.

### What changed
- **3.1** `ExactCandidates` (Core): metadata buckets (type, size, creation second [+ duration], or filename). Dropped singletons; oversized buckets are *counted*, never silently dropped. Test: 250k assets with 500 planted pairs, all found, well under the 5 s budget.
- **3.2** Scan hashes **every resource set** for bucket members and the best visual pairs. The old filter that skipped Live/RAW/edited/shared photos is gone. An asset that can't be read completely is counted as unverifiable, never as a match.
- **3.3 (safety change; owner review PENDING)** `PreservationFlag.hard` vs `.conditional` (`livePhoto`, `edited`, `raw`). A conditional-flag target is removable only with a direct, complete byte-equal link to a keeper that carries at least the same conditional flags; never for near-duplicates. The old `testProtectionFlagsFailClosed` (loop over *all* flags) was split into 8 precise tests, including `testAllFlagsAreClassifiedExactlyOnce` (a new flag can't go unclassified) and a **10,000-cluster fuzz test** (no hard flag ever leaks; conditional targets always have an equal keeper). Mutation check: removing the keeper-flag requirement makes a test fail.
- **3.4** Opt-in iCloud checking. `NetworkPolicy` is the only code that may allow a download (`allowNetwork: true` occurs only in `DigestFetcher` inside `NetworkPolicy.swift`): off by default, not on cellular/expensive/constrained connections, with a per-scan budget (1/2/5/10 GB). Local read first; download only on failure. The commit-time rehash uses the same policy. Checked per asset (the plan said per resource; an asset's resources are read back-to-back).
- **3.5** Coverage in plain words in the Exact inbox ("N photos checked in full", "M couldn't be checked, they're in iCloud. Turn on iCloud checking", skipped oversized sets).
- Live / edited / RAW shown as symbols on photo tiles; protected-reason copy explains conditional flags.

### Defects found by testing, fixed
- **Group IDs used `String.hashValue`** (randomized per launch). That would have broken the "reviewed" memory and the persisted tray across relaunches. Now a SHA-256 token; tested.
- **Post-hash recheck only looked at hard flags.** A conditional flag (e.g. "edited") appearing late with no revision change would have slipped through. The coordinator now re-runs the *full* `validateCommit` on fresh records after hashing. Test: `testProtectedFlagWithoutRevisionChangeStillAborts` now expects `unsafe(protected)`.
- My own test expectation about favorites was wrong: the favorite becomes the *keeper* (so the plain copy is removable); added a test that two favorites are never offered.

### Tests added
Core: 9 ExactCandidates, 9 flag-split/fuzz. iOS: 11 `ExactMatchingTests` (Live pair exact + preselected; different paired video not exact; paired video not local counted, not matched; edited and RAW copies findable; favorite is keeper; network never used when off; never used on an expensive connection; opt-in downloads and counts budget; budget stops downloads; stable group ids). UI: iCloud flow end to end (scan → "couldn't be checked" → opt in → rescan → the iCloud-only copy becomes a group) and menu sheet.

### Self-review
- Existing SafetyPolicy assertions changed: **one, as authorized** (`testProtectionFlagsFailClosed` → split; semantics for hard flags unchanged). **Owner must review `SafetyPolicy.swift` + that test.** The change is isolated in commit `1eb00cb` and can be reverted independently of the rest of Step 3.
- `deleteAssets`: still exactly one call site.
- Network: `isNetworkAccessAllowed = false` (thumbnails) and `= allowNetwork` (digests); `allowNetwork: true` only in `NetworkPolicy.swift`.
- Question for the owner's review: *"Is there any input where a conditional-flag asset can be preselected without complete resource equality to a keeper with the same flags?"* The fuzz test says no across 10,000 random clusters.

### 🧑 Human gate (PENDING): device check (disposable library)
Use Photos' "Duplicate" on a Live Photo, an edited photo and a normal photo; scan; expect 3 exact groups; delete one in the app (with only ONE group in the tray, see the Step 8 note); confirm Recently Deleted and the keeper. Then with iCloud Photos + Optimize Storage on: toggle iCloud checking off then on and note the coverage numbers.
