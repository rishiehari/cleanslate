# CleanSlate — Execution Plan (Steps 1–10)

**Audience:** the coding agent that implements this plan (e.g. Claude Sonnet in Claude Code), plus the human owner who signs off at the gates.
**Written:** 2026-11-05, against commit `1891668`, Xcode 26.6 / iOS 26.5 SDK.
**Status when written:** the iOS app compiles; 30/30 core tests pass on macOS; iOS test `testFeaturePrintDistanceNearZeroForSameBitmap` **fails in the simulator**, so the CI `ios` job is red.

---

## 0. How to use this plan (read first, every session)

### 0.1 Operating rules for the executing agent

1. **Do steps strictly in order.** Do not start step N+1 until step N's *Exit criteria* are met and logged. Within a step, do the tasks in the order listed.
2. **Start every session** with:
   ```bash
   git status && git log --oneline -5
   make core-test        # Step 1 adds this target. Before then: swift test --package-path Core
   ```
   Then read §0 of this file, the current step's section, and the last entry in `docs/VALIDATION_LOG.md`.
3. **Never touch a real photo library.** All deletion work runs in the **simulator**, on synthetic fixtures. Anything marked **🧑 HUMAN GATE** must be done or approved by the human owner. Stop there, write what you need into `docs/VALIDATION_LOG.md`, and end your turn with a clear request.
4. **Safety tests are append-only.** You may add tests to `Core/Tests/CleanSlateCoreTests/SafetyPolicyTests.swift`. You may **not** edit or delete an existing assertion unless this plan explicitly says so (only Step 3.3, Step 4.5 and Step 8.4 do). Every such change is a 🧑 HUMAN GATE. If a test fails, fix the code, not the test.
5. **Check every Apple API before you use it.** Do not trust memory. Check the installed SDK:
   ```bash
   SDK=$(xcrun --sdk iphonesimulator --show-sdk-path); F=$SDK/System/Library/Frameworks
   grep -rn "<SymbolName>" $F/Photos.framework/Headers $F/BackgroundTasks.framework/Headers
   grep -n "<SymbolName>" $F/Vision.framework/Modules/Vision.swiftmodule/*.swiftinterface
   ```
   If a symbol is missing or has a different signature, adapt and note it in the log. Never use private or undocumented API. In particular, **never** read `PHAssetResource`'s `fileSize` via KVC, and never use `photos-redirect://` URL schemes.
6. **Commit after each numbered sub-task**, with a message like `Step 3.2: hash Live Photo resource sets`, and keep each commit buildable. Do not push unless the human asks.
7. **Keep pure logic in `Core/`** (framework-free, runs on Linux). Put PhotoKit, Vision and UIKit code only in `App/`. Anything that decides *whether something may be deleted* goes in `Core` and gets unit tests.
8. **No network code, analytics, or third-party SDKs.** No new dependencies without a 🧑 HUMAN GATE.
9. **If you're stuck** (the same build or test failure after 3 honest fix attempts, or a needed API doesn't exist), stop and write a "BLOCKED" entry in the log with the full error and what you tried.
10. **UI work uses the installed `apple-skills` plugin** (marketplace `indie-apple-stack`). Before writing or changing any SwiftUI view, invoke the matching skill with the Skill tool and follow it. Where this plan and a skill disagree, this plan wins.
    | Skill | Use it for |
    |---|---|
    | `apple-skills:design` → `design-system` | tokens, text styles, shared components, `ContentStateView`, 300-line view limit, accessibility identifiers |
    | `apple-skills:design` → `liquid-glass` | glass on the navigation layer only (bars, the floating approval bar, toolbars), `GlassEffectContainer`, `.buttonStyle(.glassProminent)` |
    | `apple-skills:design` → `animation-patterns`, `sf-symbols` | springs, matched-geometry "card flies to tray", `.contentTransition(.numericText())`, symbol effects |
    | `apple-skills:design` → `game-feel` (haptic-design, feedback-audit) | semantic haptics service, event×channel audit |
    | `apple-skills:design` → `ux-writing` | every label, alert, empty state and the word list |
    | `apple-skills:design` → `ui-prototyping` | divergent `#Preview` variants before building the review screen |
    | `apple-skills:generators` → `preview-data-generator`, `accessibility-generator`, `screenshot-automation`, `onboarding-generator`, `permission-priming` | sample data, a11y, App Store screenshots, onboarding, Photos permission priming |
    | `apple-skills:ios` → `ui-review`, `accessibility-audit`, `navigation-patterns` | the HIG review at the end of every UI-touching step |
    | `apple-skills:testing` → `snapshot-test-setup`, `flow-walkthrough` | component snapshots, end-to-end flow checks |
11. **Every engine capability must show up in the UI.** A step that adds a capability (a new category, coverage numbers, protections, receipts) is not done until that capability has a designed surface that meets §0.4. Each step's **UX surface** subsection lists what's required.

### 0.2 Standard validation commands (Step 1 creates these Make targets)

| Command | What it does |
|---|---|
| `make core-test` | `swift test --package-path Core` |
| `make gen` | `xcodegen generate --spec project.yml` |
| `make build` | Unsigned simulator build of the app |
| `make ios-test` | XCTest + XCUITest on the first available iPhone simulator |
| `make seed` | Generate fixtures and import them into the booted simulator |
| `make ci` | `core-test` + fixture Python tests + `build` + `ios-test`, i.e. the same as GitHub CI |

### 0.3 The review protocol (run at the end of EVERY step)

Every step ends with **Validate → Review → Log**:

1. **Validate:** run `make ci` (must be green), plus the step-specific tests and manual checks listed in the step.
2. **Self-review checklist** (answer each in the log entry):
   - [ ] Did any existing `SafetyPolicyTests` assertion change? (Must be "no", unless the step authorizes it.)
   - [ ] Can any code path call `PHAssetChangeRequest.deleteAssets` without first passing `SafetyPolicy.validateCommit` / `validateBatch`, fresh revisions, and (for exact matches) rehashing right before deletion? Show the call graph: `grep -rn "deleteAssets" App`.
   - [ ] Can any new code send network requests? `grep -rn "isNetworkAccessAllowed = true\|URLSession" App` must only show the one allowed place, the Step 3 opt-in path.
   - [ ] Is there any new PhotoKit, Vision or SQLite work on the main actor inside a loop?
   - [ ] Is everything user-facing about storage labeled correctly ("verified file bytes" vs "estimate" vs "measured free space")?
3. **Automated review:** run `/code-review medium` on the step's diff (`git diff <step-start-commit>..HEAD`). Fix the confirmed findings, or explain in the log why one doesn't apply.
4. **Log:** append to `docs/VALIDATION_LOG.md`:
   ```markdown
   ## Step N — <title> — <date>
   Start commit: abc123  End commit: def456
   make ci: PASS (core 41 tests, ios 12 tests, ui 3 tests)
   Step-specific checks: <each check → PASS/FAIL + evidence>
   Self-review: <answers>
   /code-review: <n findings, n fixed, n dismissed + reason>
   Human gate: <PENDING / APPROVED by owner on date / N/A>
   Known gaps carried forward: <list>
   ```
5. If the step has a 🧑 HUMAN GATE, **stop** and ask the human. Do not continue to the next step in the same turn.

**Additional review for any step that touches UI:**
- [ ] Run `apple-skills:ios` → `ui-review` on the changed screens and fix the findings. `accessibility-audit` must pass.
- [ ] Every screen in §0.4's checklist still holds, especially "approve ≠ delete" and "nothing similar is preselected".
- [ ] Take screenshots of each changed screen in light, dark and AX3 Dynamic Type, save them to `docs/screens/stepN/`, and link them in the log.
- [ ] No raw colors, fonts, padding numbers or radii in views (SwiftLint design-system rules from Step 2B pass).

### 0.4 Experience principles and UI acceptance rules (apply to every screen)

**The promise to the customer:** *"CleanSlate finds the copies. You decide. Nothing is deleted until you say so, twice: once in CleanSlate and once in Apple's own prompt."*

**The core interaction model: Review → Approve → Tray → Delete**
1. **Review:** the app shows one group at a time. The suggested *Keep* photo is clearly marked, and the copies are marked *Delete* (exact) or left unmarked (similar).
2. **Approve:** one tap on **Approve** moves the group's Delete-marked photos into the **Deletion tray**. *Approving never deletes.* **Skip** moves on without changes, and every approve or skip can be undone right away with a toast.
3. **Tray:** a persistent toolbar badge shows "N photos · X GB ready". Opening it shows everything approved, grouped, and anything can be removed.
4. **Delete:** "Delete N photos" → one summary sheet → Apple's system prompt → a receipt. Groups that went stale since approval are pulled from the tray with a plain-language reason, never silently deleted.

**Visual and interaction rules**

| # | Rule |
|---|---|
| U1 | **Approve ≠ delete.** No single tap anywhere deletes a photo. The only path to deletion is the tray summary sheet and then Apple's prompt. |
| U2 | **Keep is always visible.** Every group shows at least one Keep photo, marked with a green `checkmark.circle.fill` badge + "Keep" label. Delete-marked photos get a red `trash.circle.fill` badge + "Delete" label, so color is never the only signal. |
| U3 | **Tap to change your mind.** Tapping any photo in a group toggles Keep/Delete. Tapping a protected photo shows *why* (e.g. "Favorite — always kept") with a `lock.fill` badge and a light warning haptic; it never toggles. The rule that a group keeps at least one Keep photo is enforced in the UI and again in Core. |
| U4 | **Exact copies are pre-marked; similar photos are not.** Exact groups open with copies marked Delete, so approving is one tap. Similar and burst groups open with only a suggested keeper, nothing marked Delete, so the user taps what to remove. Assert this in UI tests. |
| U5 | **Explain every suggestion.** Each group shows evidence chips in plain words: "Identical file", "Same burst", "Looks similar", "Different people" (warning), "Has different text" (warning). Tapping a chip opens a short explanation sheet. |
| U6 | **Big, fast, comparable photos.** Group photos fill the width. A tap-and-hold peeks full screen; double-tap or pinch opens compare mode with synchronized zoom and pan. Thumbnails for the next 3 groups are prefetched (`PHCachingImageManager.startCachingImages`), so swiping never shows a blank tile. |
| U7 | **Liquid Glass only on the navigation layer.** The floating approval bar (Skip · Approve), toolbars and the tray button use glass, all inside one `GlassEffectContainer`. Photos, cards and lists never use glass. Only the primary action (**Approve**, and **Delete N photos** in the tray) is tinted. Use the system `.glass`/`.glassProminent` button styles; no custom blur. |
| U8 | **Motion carries meaning.** When a group is approved, its Delete photos shrink into the tray button (matched geometry, snappy spring), and the tray count updates with `.contentTransition(.numericText())`. Under Reduce Motion this becomes a cross-fade and the same count change. No looping or decorative animation. |
| U9 | **Haptics vocabulary, one owner.** A single `HapticsService` (semantic events: `toggle`, `approve`, `skip`, `undo`, `blocked`, `batchDeleted`) is fired only from view models, never from views. `batchDeleted` is the rarest and biggest pattern. There's a Settings toggle to turn haptics off. |
| U10 | **Numbers never lie.** Bytes shown on review screens are *verified*. Estimates show "≈" and the word "estimated"; unknown sizes show "Size in iCloud". Verified and estimated numbers are never added together (same rule as Step 4.4). |
| U11 | **Every list or async screen uses `ContentStateView`**: scanning (skeleton, determinate progress), empty ("No copies found in the 182,340 photos checked"), error with retry, permission denied. No bare spinners and no dead ends. |
| U12 | **Progressive results.** Groups appear in the Review inbox *while* the scan runs. The user never has to wait for 100% before starting. |
| U13 | **Fully accessible.** VoiceOver reads each photo as "Keep, photo 1 of 4, 12 MB" and has custom actions Keep / Delete / Compare. Every gesture has a button equivalent. Dynamic Type up to AX5 reflows layouts (photos stack vertically). Minimum 44×44 pt touch targets. |
| U14 | **Calm, plain copy** (ux-writing). Word list: **Keep · Delete · Approve · Skip · Undo · Copy · Similar photo · Ready to delete · Free up**. Avoid: *purge, clean, junk, redundant, candidate, asset, resource, revision*. Keep the legal/technical caveats, but put them in "Learn more" sheets, not on every screen. |
| U15 | **The user can always stop.** Pause/resume the scan anywhere; leave a group half-reviewed and its state is remembered; clearing the tray asks once. |

---

## Step 1 — Green CI, testable architecture, first device run

**Goal:** a trustworthy baseline: CI green, Vision tests meaningful, PhotoKit behind a protocol so the deletion code can be tested without a real library, and the app runs once on a physical iPhone.

### Tasks

**1.1 Repo hygiene**
- Add to `.gitignore`: `CleanSlate.xcodeproj/` (XcodeGen generates it), `.venv/`, `/private/`, `*.xcresult`.
- Add Makefile targets from §0.2. `ios-test` picks a simulator the way the CI does (`xcrun simctl list devices available | awk -F'[()]' '/iPhone/{print $2; exit}'`) and uses `-derivedDataPath build/DerivedData`. Add `build/` to `.gitignore`.
- Create `docs/VALIDATION_LOG.md` with a header and the §0.3 template.

**1.2 Diagnose the Vision test failure**
- `VisualFeatures.printFeature` swallows its error (`catch { return nil }`). Temporarily add a throwing variant and, in the failing test, print the error.
- Run `make ios-test` and record the exact error in the log.
- Expected: Vision feature prints fail in the simulator because there's no Neural Engine or inference context. If the error confirms that, the fix is 1.3 plus a simulator skip. If it's something else, such as orientation or a nil `cgImage`, fix the root cause.

**1.3 Migrate to the Swift Vision API (iOS 18+)**
- Rewrite `App/Services/VisualFeatures.swift` to use `GenerateImageFeaturePrintRequest`, `CalculateImageAestheticsScoresRequest` and `DetectFaceCaptureQualityRequest` (all checked in the iOS 26.5 SDK). `FeaturePrintObservation.distance(to:) throws -> Double` exists, and `FeaturePrintObservation` is `Codable`, which Step 5 will use to store feature prints.
- Make the functions `async throws` and return errors instead of `nil`, so callers can tell "unavailable" from "failed".
- Keep the aesthetics normalization `(score+1)/2` and the worst-face rule.
- In `iOSTests`, guard Vision model tests:
  ```swift
  #if targetEnvironment(simulator)
  throw XCTSkip("Vision feature prints require device hardware; covered by device test plan")
  #endif
  ```
  Only skip if 1.2 confirmed it's a simulator limitation. The dHash test must still run in the simulator.

**1.4 Testability seam: `PhotoLibraryClient`**
- Create `App/Services/PhotoLibraryClient.swift`:
  ```swift
  protocol PhotoLibraryClient: Sendable {
      func authorizationStatus() -> PHAuthorizationStatus
      func requestAccess() async -> PHAuthorizationStatus
      func inventory(limit: Int?) async -> (photos: [PhotoSnapshot], totalVisible: Int)
      func snapshots(ids: [String], inspectAlbums: Bool) async -> [String: PhotoSnapshot]
      func thumbnail(id: String, target: CGFloat) async -> UIImage?
      func digests(id: String, allowNetwork: Bool) async throws -> [ResourceDigest]
      func delete(ids: [String]) async throws          // wraps performChanges + deleteAssets
  }
  ```
- `PhotoKitLibraryClient` is the existing `PhotoCatalog` logic moved behind the protocol. `PhotoDeletionCoordinator` and `CleaningViewModel` take a `PhotoLibraryClient` in `init` (default: the PhotoKit implementation).
- Because `PhotoDeletionCoordinator` currently re-snapshots `PHAsset`s directly, change it to use `snapshots(ids:inspectAlbums:)` so all of its logic runs against the protocol.
- Create `iOSTests/Fakes/FakePhotoLibrary.swift`. It's an actor or `@unchecked Sendable` class with an in-memory asset table. You can script revisions, flags, digests, "not local" failures and deletion outcomes (`.success`, `.userCancelled`, `.error`), and it records every `delete(ids:)` call.

**1.5 Deletion coordinator tests (the most important tests in the app)**
Add `iOSTests/DeletionCoordinatorTests.swift` using the fake library:
- `testExactDuplicateDeletesOnlySelected`: the keeper survives and `delete` is called with exactly `[b]`.
- `testStaleRevisionAbortsBeforeDelete`: change the revision between review and commit; `delete` is never called.
- `testKeeperVanishedAborts`
- `testBytesChangedAtCommitAborts`: the digests at commit differ from review.
- `testBecameFavoriteDuringHashAborts`: the flag changes during the rehash; the second check catches it.
- `testUserCancelsSystemPrompt`: `delete` throws; no success receipt; the group stays.
- `testConcurrentCommitIsRejected`: two concurrent commits; the second throws `.busy`.
- `testLimitedAccessNeverCountsAsVerifiedRemoval`
- `testSimilarRequiresManualReview`: a similar group with an unreviewed selection is blocked.

**1.6 CI**
- Update `.github/workflows/build.yml` to call `make` targets. Upload the `.xcresult` as an artifact on failure. Pin the runner to `macos-15` (or newer) and select the newest installed Xcode explicitly.

**1.7 🧑 HUMAN GATE — first physical device run**
The human signs the app with their personal team, installs it on an iPhone with a **disposable** library (a spare device, or a fresh test Apple ID with iCloud Photos off), seeds about 30 photos including 3 pairs duplicated with Photos' "Duplicate" action, and runs the "Build and permissions" and "Deletion canary" sections of `docs/DEVICE_TEST_PLAN.md`. The agent prepares the checklist in the log and waits.

### Validation
- `make ci` green locally, and the GitHub Actions run is green.
- The new coordinator tests pass (at least 9).
- The Vision tests pass on device (from the human run) or are skipped in the simulator with a recorded reason.

### Review focus
Show that the protocol refactor didn't change behavior: every guard that was in `PhotoDeletionCoordinator.commit` before still exists. Diff it side by side and paste the list of guards into the log.

### Exit criteria
CI green · coordinator tests in place · device checklist results logged by the human.

---

## Step 2 — Product positioning vs Apple's built-in Duplicates (decision step)

**Goal:** lock the product's scope so the engine work in Steps 3–8 targets what users can't already do for free in the Photos app.

**Default decision** (the human may override at the gate): CleanSlate is *"the storage-recovery and photo-culling tool Apple Photos doesn't have."* Keep byte-exact duplicates as one feature, but lead with **bursts and similar shots, videos, screenshots, large files, and an honest storage receipt**. Tell users that Photos → Collections → Utilities → Duplicates can *merge* exact copies, which PhotoKit can't do.

### Tasks

**2.1** Write `docs/PRODUCT.md` (at most 2 pages) covering: target user (50k–250k photos, iCloud Photos on, storage pressure); problems ranked by storage impact; the feature categories (Exact copies, Similar & bursts, Videos, Screenshots, Large files, Receipts); explicit **non-goals** (no cloud, no accounts, no automatic deletion of non-exact items, no metadata merge); success metrics (verified bytes recovered per session, harmful-deletion reports = 0, review throughput in groups/minute).

**2.1b Minimum iOS version (decision, 🧑 confirmed at this step's gate).** Recommended: **raise the deployment target from iOS 18 to iOS 26.**
- Liquid Glass (`.glassEffect`, `GlassEffectContainer`, `.glassProminent`) and `BGContinuedProcessingTaskRequest` are iOS 26+.
- iOS 26 runs on iPhone 11 and newer.
- Supporting iOS 18 would mean building and testing two visual systems.

If the human keeps iOS 18, every glass use in Step 2B gets an `if #available(iOS 26, *)` path with a `.regularMaterial` fallback, and the UI tests run on both OS versions. Update `project.yml` and `Core/Package.swift` (`.iOS(.v26)`) accordingly.

**2.2 Dashboard information architecture (structure only; visuals come in Step 2B).** Restructure `DashboardView` into category cards: Exact copies · Similar & bursts · Videos · Screenshots · Large files. Each card shows a count, verified bytes, unverified count, and "Review". Categories that aren't built yet show "Coming in a later build" and are hidden behind `#if DEBUG`. Move the scan progress into a compact header.

**2.3 Onboarding** (3 screens, shown once, can be reopened from the menu):
1. Privacy: nothing leaves the phone.
2. How deletion works: Apple's confirmation prompt, Recently Deleted keeps items 30 days, iCloud deletion syncs to all devices.
3. Tip: Photos' own Duplicates album can merge exact copies. Show text instructions only, no deep link.

Store "onboarding seen" in `UserDefaults` and note that this needs a privacy manifest entry in Step 10.

**2.4 UI test target + launch-argument test mode**
- Add a `CleanSlateUITests` target to `project.yml`.
- Add an app launch argument `-uiTestingFakeLibrary`. In DEBUG builds only, it injects `FakePhotoLibrary` with a deterministic scenario (move the fake into a shared `App/Debug/` folder compiled only in DEBUG).
- UI tests: `testOnboardingShownOnceThenDashboard`, `testCategoryCardsRender`, `testDeniedPermissionShowsSettingsCard`.

### Validation
`make ci` green, including the 3 UI tests. Take simulator screenshots of onboarding and the dashboard with `xcrun simctl io booted screenshot`, save them under `docs/screens/step2/`, and link them in the log.

### 🧑 HUMAN GATE
The owner approves `docs/PRODUCT.md` and the screenshots. If they change the positioning, update Steps 3–8 here before continuing.

### Exit criteria
PRODUCT.md approved · minimum iOS version decided · UI test infrastructure works · the dashboard is organized by category.

---

## Step 2B — Design system and the signature Review → Approve → Tray experience

**Goal:** before the engine grows, build the design system and the one interaction customers will spend 90% of their time in: reviewing a group and tapping **Approve**. It should feel like a first-party Apple app: calm, fast, obvious, and the user stays in control. Everything here runs on `FakePhotoLibrary` data, so it doesn't depend on Steps 3–8. Those steps plug real groups into it.

**Load first:** `apple-skills:design` (design-system, liquid-glass, animation-patterns, game-feel, ux-writing, ui-prototyping, sf-symbols, typography) and `apple-skills:generators` (preview-data-generator).

### Tasks

**2B.1 Design tokens and text styles** (`App/DesignSystem/`, following the design-system skill)
- `Tokens.swift`: `Spacing` (xxs 2 · xs 4 · s 8 · m 16 · l 24 · xl 32), `Radius` (s 8 · m 14 · l 22 · photo 12 · pill), `IconSize`.
- Role-named colors in the asset catalog with light, dark and increased-contrast variants: `textPrimary`, `textSecondary`, `surfaceBackground`, `surfaceCard`, `keepAccent` (green), `deleteAccent` (red), `protectedAccent` (gray), `warningAccent` (orange), `actionPrimary` (brand tint; keep the current teal `#1F8C6B` unless the human picks another).
- `AppTextStyle` for the system SF font only (no custom fonts): `heroNumber` (`.largeTitle`, rounded, bold, monospaced digits), `title`, `groupTitle`, `body`, `caption`, `chip`, `badge`. All Dynamic Type-relative.
- Add the skill's SwiftLint rules (`rules/swiftlint.yml`) as `.swiftlint.yml` with the token folder excluded, write a baseline, and add `swiftlint lint --strict --baseline .swiftlint-baseline.json` to `make ci` (`brew install swiftlint`; skip with a warning if it's missing locally, but require it in CI).

**2B.2 Shared components** (`App/DesignSystem/Components/`, one file each, each under 300 lines, with a `#Preview` per state)

| Component | What it is |
|---|---|
| `PhotoTile` | Async thumbnail with a fixed aspect ratio, skeleton shimmer while loading (static under Reduce Motion), and an "In iCloud" state. Overlay slot for a badge. |
| `DecisionBadge` | `.keep` / `.delete` / `.protected(reason)` / `.undecided`. Icon + label, always both (U2). |
| `EvidenceChip` | `.identicalFile`, `.sameBurst`, `.looksSimilar`, `.differentPeople`, `.differentText`, `.inICloud`. Tappable → explanation sheet. |
| `StorageHero` | The big "X GB you can free" number with a verified/estimated split (U10), using `.contentTransition(.numericText())`. |
| `CategoryCard` | Icon, title, count, verified bytes, "Review" chevron. Content layer, so **no glass**. |
| `ApprovalBar` | Floating bottom bar: **Skip** (`.glass`) · **Approve** (`.glassProminent`, tinted) inside a `GlassEffectContainer`, respecting the safe area and scroll edge effect. Also shows an "Approve 4 copies · 38 MB" subtitle. |
| `TrayButton` | Toolbar button: `tray.full` symbol + count badge, with a symbol bounce effect when items arrive (U8). |
| `UndoToast` | Glass capsule, "Approved 3 copies · Undo", auto-dismisses after 4 s, VoiceOver announces it. |
| `ContentStateView` | From the design-system skill, with scanning/empty/error/permission states (U11). |
| `ConfirmSheet` | The tray's final summary sheet (detents `.medium`/`.large`). |

**2B.3 `HapticsService`** (from game-feel/haptic-design): semantic events `toggle`, `approve`, `skip`, `undo`, `blocked`, `batchDeleted`. Use `.sensoryFeedback` for the simple ones; Core Haptics only if `batchDeleted` needs a custom pattern. Lazy engine, capability check, a Settings toggle, injected into view models (U9). Unit test: firing with haptics off is a no-op.

**2B.4 Prototype the Review screen first** (ui-prototyping skill, Stage 1 + 2)
- Build **5 divergent `#Preview` variants** of the group review screen, each with realistic sample data (preview-data-generator: groups of 2, 4 and 12 photos, a protected photo, an iCloud-only photo, a long burst):
  1. **"Card Stack"**: one group per full-screen card, swipe up = approve, left = skip, like a deck.
  2. **"Hero + Strip"**: a large Keep photo on top, a horizontal filmstrip of the others below, tap to toggle.
  3. **"Grid Triage"**: a 2-column grid of the whole group with badges on each tile; the Photos-app feel.
  4. **"Side by Side"**: the keeper and one copy at a time, A/B style, best for similar shots.
  5. **"Inbox List"**: a vertical list of groups with inline thumbnails, approve from the row; fastest for exact copies.
- `xcodebuild build` must pass. Write `docs/design/PROTOTYPE.md` with a variant table (preview name · organizing idea · strengths · risks) and **screenshots of each variant** in light and dark (render with `ImageRenderer` in a DEBUG test, or simulator screenshots via a `-prototypeVariant N` launch argument).
- **🧑 HUMAN GATE (design choice):** the human picks a base and any remix ("Hero + Strip for similar groups, Inbox List for exact copies"). Recommendation to offer: **Inbox List for exact copies** (bulk, one tap per row, plus "Approve all") and **Hero + Strip with Side-by-Side compare for similar and bursts**. Record the decision in `PROTOTYPE.md`.

**2B.5 Build the chosen flow** (fake data, end to end)
- **Home:** `StorageHero` + category cards + a compact scan status (determinate progress, pause/resume) + `TrayButton` in the toolbar. Large navigation title "CleanSlate".
- **Review inbox per category:** progressive list (U12), sorted by verified bytes for exact copies and by date for similar; a "Reviewed" filter.
- **Group review screen:** the chosen variant. Tap to toggle (U3), evidence chips (U5), `ApprovalBar`, next-group prefetch (U6), and swipe or keyboard shortcuts if part of the chosen design.
- **Exact copies "Approve all":** a list header button, "Approve all 214 copies · 3.1 GB". It opens a sheet listing the groups (each one can be excluded), then puts them all in the tray. It still doesn't delete.
- **Compare mode:** full-screen, 2-up with synchronized zoom and pan (one shared `MagnifyGesture` + offset state), and a swipe to change the paired photo. It's reachable from the review screen by double-tap and by a button.
- **Tray:** a sheet or pushed screen listing approved groups (Keep thumbnail + "3 copies"), swipe to remove a group, and a total. The primary button is "Delete 214 photos" (`.glassProminent`, tinted with `deleteAccent`). Tapping it opens the `ConfirmSheet`: count, verified bytes, "Deleted photos stay in Recently Deleted for 30 days", "Deleting from iCloud Photos removes them from all your devices". **Continue** hands off to Apple's prompt. In Step 2B this calls the fake library; Step 8 wires the real batch coordinator.
- **Receipt:** after deletion, a short success screen with the animated freed-bytes number, `batchDeleted` haptic, "View history", and a "Remember to empty Recently Deleted to free the space now" tip. This is the only celebration in the app (rarity rule from game-feel).
- **Approvals persistence:** the tray and per-group decisions persist across relaunches. Use a JSON file in Application Support for now; Step 5 moves it to the `reviews` table. At commit time, every tray item is revalidated (Steps 6 and 8).

**2B.6 Copy pass** (ux-writing skill): write `docs/design/WORD_LIST.md` (approved term · avoid · definition) using U14. Rewrite the existing copy in `ReviewGroupView` and `DashboardView` (currently long and technical), keeping every honest caveat but moving the details into "Learn more" sheets. Every alert must pass the scannability test (title + buttons alone explain it).

**2B.7 Permission priming and onboarding polish:** use `generators/permission-priming` to explain *why* full Photos access gives better results *before* the system prompt. Limited access is supported and explained, never punished. Restyle the Step 2 onboarding with the tokens.

### Tests
- **Snapshot tests** (`apple-skills:testing` → snapshot-test-setup) for every component state in light, dark and AX3. This needs a test-only dependency (`pointfreeco/swift-snapshot-testing`), so it's a **🧑 HUMAN GATE**. If declined, use `ImageRenderer`-based PNG attachments and do the review by hand.
- **UI tests** (fake library; elements found by `accessibilityIdentifier`, never by visible text):
  - `testExactGroupOpensPreMarked_OneTapApprove_MovesToTray`: tray count +N; `delete` **not** called.
  - `testSimilarGroupOpensWithNothingMarkedDelete` (U4).
  - `testTapTogglesKeepDelete_cannotRemoveLastKeep` (U3).
  - `testProtectedTapShowsReasonAndDoesNotToggle`.
  - `testUndoToastRevertsApproval`.
  - `testApproveAllExact_thenTrayDelete_callsFakeDeleteOnceWithAllIDs`.
  - `testCancelInConfirmSheet_deletesNothing`.
  - `testTrayPersistsAcrossRelaunch`.
  - `testReduceMotionStillUpdatesTrayCount` (launch arg forcing reduce motion).
  - `performAccessibilityAudit()` on Home, Review, Compare, Tray and Confirm.
- **Flow walkthrough** (`apple-skills:testing` → flow-walkthrough): Home → category → group → approve ×3 → undo → tray → confirm → receipt, with no dead ends and back navigation working everywhere.
- **Performance:** scrolling an inbox of 2,000 fake groups shows no hitches over 100 ms (Instruments Animation Hitches, simulator); the next group's photos render in under 150 ms after approve (signpost).

### 🧑 HUMAN GATE (feel check on device)
The human installs the build on a real iPhone (fake-data mode, `-uiTestingFakeLibrary`), runs the flow for 5 minutes, and rates: *Is it obvious what will be kept? Does Approve feel safe? Is anything slow, confusing or ugly?* The agent records the feedback, fixes it, and only then exits the step. If needed, add a DEBUG-only tuning panel for the approve animation springs (ui-prototyping Stage 3).

### Exit criteria
Design system and lint in CI · the chosen Review design is built end to end on fake data · every U1–U15 rule is covered by a test or a logged manual check · the human feel check passes.

---

## Step 3 — Exact matching that works on real libraries

**Goal:** exact-duplicate detection that covers Live Photos, edited photos, RAW and iCloud-optimized libraries, while staying byte-verified.

**Current problems:**
1. `CleaningViewModel.swift:777` skips hashing for `.livePhoto/.raw/.edited/.shared`, and `SafetyPolicy` blocks *any* flag. So most iPhone camera photos can never be exact matches.
2. Exact candidates come only from the top 240 dHash pairs.
3. Originals that live only in iCloud are never checked.

### Tasks

**3.1 Metadata-bucket candidate generation (Core)**
- Add `Core/Sources/CleanSlateCore/ExactCandidates.swift`. Input: `[ExactKey]`, where `ExactKey` is `(id, mediaType, pixelWidth, pixelHeight, creationSecond: Int64?, durationMillis: Int64?, primaryResourceUTI, primaryOriginalFilename)`. Output: buckets of IDs that *might* be byte-identical, grouped by `(mediaType, w, h, creationSecond)` with a second pass by `(mediaType, w, h, originalFilename)`. Drop singleton buckets. Cap buckets at 64 members; larger ones are flagged as "oversized" and skipped with a counter.
- This is how exact matching scales: only bucket members get hashed, never the whole library.
- Tests: buckets are order-independent; nil dates fall through to the filename pass; oversized buckets are counted, not silently dropped; 250k random keys with 500 planted duplicate pairs finds all 500 in under 2 s on macOS (`measure {}`).

**3.2 Hash full resource sets for every media subtype (App)**
- Remove the flag pre-filter in the hashing loop. `digests(id:allowNetwork:)` already hashes *all* `PHAssetResource`s: the photo, paired video, adjustment data and full-size renders.
- Record which resources were present. A Live Photo whose `.pairedVideo` isn't local counts as **incomplete**, never as exact.

**3.3 Split preservation flags into "hard" and "conditional" (Core — safety change)**
- Add to `Models.swift`:
  ```swift
  extension PreservationFlag {
      /// Always blocks deletion of the target.
      static let hard: Set<PreservationFlag> = [.favorite, .hidden, .userBurstPick, .shared,
          .curatedAlbum, .incompleteResources, .unknownOwnership, .uncertainMetadata]
      /// Allowed only when the target's FULL resource set is byte-identical to a keeper's
      /// and that keeper carries the same conditional flags.
      static let conditional: Set<PreservationFlag> = [.livePhoto, .edited, .raw]
  }
  ```
- In `SafetyPolicy.evaluate`, replace `guard target.flags.isEmpty` with: if the target has any hard flag → `.protected`. If it has a conditional flag → allowed only when there's a direct `exactResources` + `completeResourceEquality` link to a keeper whose `flags ⊇ target.flags ∩ conditional`. Otherwise `.protected`.
- Apply the same rule in `validateCommit`, which currently has its own `record.flags.isEmpty` check.
- **Authorized test change (🧑 HUMAN GATE):** split `testProtectionFlagsFailClosed` into:
  - `testHardFlagsAlwaysBlock`: loops over `PreservationFlag.hard`, unchanged semantics.
  - `testConditionalFlagBlocksWithoutMatchingKeeper`: target Live Photo, keeper not Live Photo → `.protected`.
  - `testConditionalFlagBlocksWithoutCompleteEquality`: both Live Photos, evidence `exactResources` but `completeResourceEquality: false` → not preselected.
  - `testConditionalFlagAllowedWithMatchingExactKeeper`: both Live Photos with complete equality → preselected.
  - `testConditionalFlagNeverAllowedForNearDuplicate`: both Live Photos, `verifiedNearDuplicate` with p = 0.99999 and the gate enabled → `.protected`.
  - `testAllFlagsCovered`: `hard ∪ conditional == Set(PreservationFlag.allCases)` and the two sets don't overlap. This stops a future flag from being silently unclassified.
- Leave the `PhotoDeletionCoordinator` post-hash check (`flags.isEmpty || id == keeper`) in place, but route it through the same Core function so there's only one source of truth.

**3.4 Opt-in "Verify iCloud originals" (the only network path in the app)**
- Add a Settings screen toggle, off by default: *"Download originals to verify duplicates (Wi-Fi only). Downloads are temporary and not uploaded anywhere."*
- In the PhotoKit client, pass `allowNetwork: true` only if the toggle is on **and** `NWPathMonitor` reports `!isExpensive && !isConstrained`. Re-check the path before each resource. Use the `PHAssetResourceRequestOptions.progressHandler` for UI progress.
- Add a per-session download budget, default 2 GB, that the user can change. Stop and report when it's reached.
- Add one helper, `NetworkPolicy.allowsOriginalDownload() -> Bool`, and make it the only place that can return `true`. The §0.3 grep check must find `isNetworkAccessAllowed = true` only next to it.

**3.5 Coverage reporting**
`ScanStatistics` gains: `exactBucketsFound`, `exactAssetsHashed`, `exactAssetsUnverifiable` (cloud-only, downloads off), `exactAssetsIncomplete`, `bucketsOversized`. The Exact card shows "N copies verified · M couldn't be checked (in iCloud) — Turn on verification".

**3.6 Optional: "same pixels, different details" tier (review-only)**
Only if the time budget allows. When both originals are local and still images, decode them with `CGImageSource` at full size, hash the pixel buffer, and on a match emit `PairRelation.visuallySimilar` with a UI badge "Same image, different photo details". It is **never preselected**. Skip it and log it as deferred if it adds more than a day.

### UX surface (uses Step 2B components)
- Exact groups for Live, edited and RAW photos show their type as a small symbol on `PhotoTile` (`livephoto`, `slider.horizontal.3`, `camera.aperture`) with VoiceOver labels.
- Coverage appears on the Exact copies card and at the top of its inbox: "1,240 copies verified · 3,880 photos in iCloud weren't checked". The second part is a button that opens the "Verify iCloud originals" explainer sheet with the toggle, the Wi-Fi-only note and the budget slider.
- While iCloud verification runs: determinate progress with "Downloaded 640 MB of 2 GB", pause/resume, and no blocking modal.
- Protected photos show the reason in plain words via `DecisionBadge.protected` ("Favorite — always kept", "Edited — kept unless the other copy has the same edits").

### Validation
- Core: all new tests plus the existing ones pass.
- Fake library tests (`ExactMatchingTests.swift`):
  - A Live Photo pair with identical photo and video resources → exact group, preselected.
  - Same photo but different paired video → not exact.
  - Paired video not local → counted as `exactAssetsIncomplete`.
  - Download toggle off → `allowNetwork` is never true (assert on the fake's recorded calls).
  - Toggle on but the network is expensive → never true.
  - Edited duplicate where the original isn't edited → protected.
- Simulator: `make seed`, then scan. The `exact_copy` fixtures appear as exact groups, and the `unique_*` fixtures never appear in the Exact category.
- **🧑 HUMAN GATE (device, disposable library):** use the Photos app "Duplicate" action on a Live Photo, an edited photo and a normal photo; scan; confirm all 3 appear as exact; delete one through the app; confirm it's in Recently Deleted and the keeper is unchanged. Also try with iCloud Photos + Optimize Storage on, toggle off then on, and note the coverage numbers.

### Review focus
A line-by-line diff review of `SafetyPolicy.swift` by the human (the gate in 3.3). Ask: *"Is there any input where a conditional-flag asset can be preselected without complete resource equality to a keeper with the same flags?"* Add a randomized test that fuzzes 10,000 random clusters (flags, evidence types, probabilities) and checks that this invariant holds.

### Exit criteria
Live, edited and RAW exact duplicates work end-to-end on device · the network path is opt-in, Wi-Fi only, and has a budget · the safety diff is approved.

---

## Step 4 — Videos, screenshots, screen recordings, large files

**Goal:** go after the biggest sources of storage.

### Tasks

**4.1 Inventory all media**
- Fetch `.image` and `.video`. `PhotoSnapshot` gains `mediaType`, `durationSeconds`, `subtypes` (raw `PHAssetMediaSubtype` value) and `isLocallyAvailable` (best effort).
- Checked subtypes in iOS 26.5 SDK: `.photoScreenshot` (1<<2), `.photoLive` (1<<3), `.videoScreenRecording` (1<<19), `.videoHighFrameRate`, `.videoTimelapse`, `.videoCinematic`, `.spatialMedia`.
- Add `PreservationFlag` handling for `.videoCinematic` and `.spatialMedia` (classify as `conditional`; `testAllFlagsCovered` will force this decision).

**4.2 Exact video duplicates**
These reuse Step 3: `ExactKey.durationMillis` buckets, then full-resource hashing. Videos are large, so hash at most 4 at a time, show per-file progress, and allow cancellation.

**4.3 Similar videos (review-only)**
For pairs in the same `(duration ± 1 s)` or `(dims, creation ± 60 s)` bucket, grab frames at 10/50/90% with `AVAssetImageGenerator`. Request the AVAsset with network disabled; if it isn't local, skip it and count it. Compute feature prints; a match needs all 3 distances under the threshold. The relation is `visuallySimilar` and is never preselected. Also cover trimmed copies: same start frame, different durations.

**4.4 Sizes without private API**
- Local videos: `PHImageManager.requestAVAsset` with network off → if `AVURLAsset`, read `URLResourceValues.fileSize` from its URL → label it "verified local file size".
- Photos and videos already hashed: use the streamed byte count (already verified).
- Everything else: "Size unknown (in iCloud)". Optionally show a **range** estimate from duration and resolution, labeled "estimate".
- Never mix these in one total. The UI shows *verified* and *estimated* separately.

**4.5 Standalone (keeper-less) deletion policy (Core — safety change, 🧑 HUMAN GATE)**
Screenshots, screen recordings and large videos have no keeper, and `SafetyPolicy` currently *requires* one. Add a separate function. Do not loosen the existing one.
```swift
public struct StandaloneDeletionPlan: Sendable {
    public let selectedIDs: Set<String>
    public let expectedRevisions: [String: String]
    public let individuallyConfirmedIDs: Set<String>   // user tapped each one, or "select all" + typed count
    public let wasExplicitlyConfirmedByUser: Bool
}
extension SafetyPolicy {
    public static func validateStandalone(_ plan: StandaloneDeletionPlan,
                                          currentByID: [String: AssetRecord]) -> ReviewReason?
}
```
Rules: explicit confirmation is required; every selected ID must be in `individuallyConfirmedIDs`; revisions must be fresh; **any** hard flag blocks; conditional flags *do* block here (no keeper exists). Add 8 or more tests that mirror the `validateCommit` tests. Preselection for standalone categories is **always empty**.

**4.6 UIs** (all use Step 2B components and the same tray; standalone items go into the tray as "single items" with no Keep photo)
- **Screenshots:** a Photos-style grid grouped by month in sticky headers, oldest first. Tap to select (a check badge, not a red Delete badge, since there's no keeper), drag-to-select across tiles like the Photos app, an "Older than 30 days" filter chip, and an `ApprovalBar` reading "Approve 37 screenshots · 84 MB". Nothing is preselected.
- **Large files:** a list sorted by verified size, then estimated size, with `≈` labels (U10). Each row: thumbnail, duration, size, date. Tap opens an inline `VideoPlayer` preview (local only; iCloud items show "Preview needs download" and are never auto-downloaded).
- **Screen recordings:** same as Large files, filtered by subtype.
- **Similar videos:** reuse the similar-group review screen, with a 3-frame strip per video instead of one thumbnail and the duration shown.
- **Home:** the Videos, Screenshots and Large files cards come out of DEBUG and show live counts.

### Validation
- Fixtures: add `scripts/make_video_fixtures.sh`. It needs `brew install ffmpeg` (dev-only; check it exists, otherwise exit 2 with instructions) and generates `base.mp4`, `exact_copy.mp4` (byte copy), `reencoded.mp4`, `trimmed.mp4` and `different.mp4`. Update `make seed` to `simctl addmedia` them.
- Simulator: the exact video copy → Exact; re-encoded and trimmed → Similar videos (review-only); different → nothing.
- Core tests for `validateStandalone`; fake library tests for size labeling (verified, estimated and unknown never get summed together).
- UI test: in fake mode, screenshots → select 3 → review → the confirmation shows 3; `delete` gets exactly those 3.
- **🧑 HUMAN GATE (device):** take 5 real screenshots and 1 screen recording on the test device; confirm they're categorized correctly (simulator imports don't carry the screenshot subtype); delete 2; confirm the outcome.

### Review focus
`validateStandalone` must not be reachable from the duplicate flow, and `validateCommit` must not be reachable from the standalone flow. Check with grep and add a test-only call-site assertion.

### Exit criteria
All media types are inventoried · sizes are labeled honestly · the standalone policy is approved and tested.

---

## Step 5 — A scan engine for 250k items

**Goal:** full-library coverage, resumable, incremental, off the main thread, within memory and thermal limits.

### Tasks

**5.1 Swift 6 strict concurrency**
In `project.yml` set `SWIFT_VERSION: '6.0'` and `SWIFT_STRICT_CONCURRENCY: complete` for the app and tests. Fix all diagnostics *before* starting the engine work, and commit that on its own. The main actor is for UI only.

**5.2 `LibraryStore` (SQLite, WAL, versioned migrations)**
Replace `LocalFeatureIndex` with `App/Store/LibraryStore.swift`, an actor that owns one connection with `PRAGMA journal_mode=WAL; foreign_keys=ON`. Schema v1:
```sql
CREATE TABLE meta(key TEXT PRIMARY KEY, value BLOB);            -- schema_version, change_token, scan_checkpoint
CREATE TABLE assets(
  id TEXT PRIMARY KEY, revision TEXT NOT NULL, media_type INTEGER, subtypes INTEGER,
  width INTEGER, height INTEGER, created_s INTEGER, duration_ms INTEGER, burst_id TEXT,
  flags INTEGER NOT NULL, original_filename TEXT, primary_uti TEXT,
  local_state INTEGER, inventoried_at REAL, deleted INTEGER NOT NULL DEFAULT 0);
CREATE INDEX assets_exact ON assets(media_type, width, height, created_s);
CREATE INDEX assets_time  ON assets(created_s);
CREATE INDEX assets_burst ON assets(burst_id) WHERE burst_id IS NOT NULL;
CREATE TABLE features(
  asset_id TEXT PRIMARY KEY REFERENCES assets(id) ON DELETE CASCADE, revision TEXT NOT NULL,
  dhash INTEGER, band0 INTEGER, band1 INTEGER, band2 INTEGER, band3 INTEGER,
  featureprint BLOB, quality_json TEXT, feature_version INTEGER NOT NULL);
CREATE INDEX f_b0 ON features(band0); CREATE INDEX f_b1 ON features(band1);
CREATE INDEX f_b2 ON features(band2); CREATE INDEX f_b3 ON features(band3);
CREATE TABLE digests(
  asset_id TEXT PRIMARY KEY REFERENCES assets(id) ON DELETE CASCADE, revision TEXT NOT NULL,
  signature TEXT, logical_bytes INTEGER, completeness INTEGER, verified_at REAL);
CREATE TABLE groups(id TEXT PRIMARY KEY, kind INTEGER, state INTEGER, created_at REAL, updated_at REAL);
  -- state: 0 fresh, 1 stale, 2 dissolved, 3 resolved
CREATE TABLE group_members(group_id TEXT REFERENCES groups(id) ON DELETE CASCADE,
  asset_id TEXT, role INTEGER, revision_at_grouping TEXT, PRIMARY KEY(group_id, asset_id));
CREATE INDEX gm_asset ON group_members(asset_id);
CREATE TABLE reviews(group_id TEXT PRIMARY KEY, decision INTEGER, decided_at REAL, member_revisions TEXT);
CREATE TABLE receipts(id TEXT PRIMARY KEY, created_at REAL, payload_json TEXT);
```
- `dhash` is stored as INTEGER via a bit-pattern cast (`Int64(bitPattern:)`).
- Feature prints are stored as the `Codable` `FeaturePrintObservation` encoded with `PropertyListEncoder` (binary), and only for assets in candidate pairs.
- File protection: `completeUntilFirstUserAuthentication`. Mark the DB `isExcludedFromBackup = true`, since it's a rebuildable cache.
- Migrations live in an ordered array keyed by `schema_version`. Test: create v1 → migrate → data still there.

**5.3 Paginated, checkpointed inventory**
Iterate the `PHFetchResult` in chunks of 1,000 inside `autoreleasepool`, upsert each chunk in one transaction, and write `scan_checkpoint` after each chunk. When killed and relaunched, resume from the checkpoint. Don't keep the whole library in memory; the UI reads counts from SQL.

**5.4 Incremental updates via persistent change history**
Checked in the SDK: `PHPhotoLibrary.currentChangeToken`, `fetchPersistentChangesSinceToken:error:` (iOS 16+), and `PHPhotosErrorPersistentChangeTokenExpired = 3105`.
- After a full inventory, archive `currentChangeToken` (NSSecureCoding) into `meta`.
- On launch and on `photoLibraryDidChange`, fetch persistent changes since the token. For each change, call `changeDetails(for: .asset)` and apply its inserted, updated and deleted IDs to the store. Then save the new token.
- On a token-expired error, do a full re-inventory and log the counter.

**5.5 Candidate generation at scale (no caps)**
- Exact: SQL over `assets_exact`, with buckets from Step 3's `ExactCandidates`.
- Near: for each band, `SELECT asset_id, dhash FROM features WHERE bandK = ?` per bucket, skipping buckets over 256. Hamming ≤ 10 → candidate. Also time windows (±12 s) and bursts.
- Stream candidates in priority order (burst → small Hamming distance → time) through a bounded `TaskGroup` (width = `min(4, activeProcessorCount/2)`) for Vision checks. Write groups to the store incrementally, and have the UI page groups from SQL.
- **Remove** the `prefix(240)` and `>= 150` caps.

**5.6 Resource governance**
- Watch `ProcessInfo.thermalState`: at `.serious` pause Vision and hashing; at `.critical` stop and checkpoint.
- Watch `os_proc_available_memory()`: below 150 MB, drain the work queue to width 1.
- Watch Low Power Mode: show a banner and offer to pause.
- All pauses are visible in the UI ("Paused: device is warm").

**5.7 Background execution**
- `BGProcessingTaskRequest` identifier `org.cleanslate.free.scan` (`requiresExternalPower = true`) for overnight incremental scans. Add `BGTaskSchedulerPermittedIdentifiers` and `UIBackgroundModes: [processing]` through `project.yml` `info.properties`.
- On iOS 26+: `BGContinuedProcessingTaskRequest(identifier:title:subtitle:)` (checked in SDK; identifier must use the wildcard form `org.cleanslate.free.continued.*`) for a user-started "keep scanning when I leave the app", with progress reported to the system UI. Wrap it in `if #available(iOS 26, *)`.
- The expiration handler checkpoints and finishes cleanly.

**5.8 Scale harness**
- `iOSTests/ScaleTests.swift` with `FakePhotoLibrary.synthetic(count: 250_000, plantedExact: 2_000, plantedNear: 2_000, seed: 42)`. It asserts that 100% of planted exact pairs are found and that ≥ 99% of planted near pairs with Hamming ≤ 8 become candidates. It records wall time and peak memory with `XCTMemoryMetric` and `XCTClockMetric`.
- `scripts/seed_simulator_bulk.sh N`: generates N small JPEGs with the Python generator (add a `--bulk` mode) and imports them in batches of 200. Use N = 10,000 for a simulator smoke test.

### UX surface
- **Progressive inbox (U12):** groups stream into the Review inboxes from the store as they're found. The Home cards' counts and `StorageHero` animate upward live (`.numericText`, throttled to about 2 updates per second).
- **Scan status** on Home: a phase label in plain words ("Looking through 182,340 photos", "Checking 1,204 possible copies") with determinate progress, a pause/resume button, and a reason when paused ("Paused — iPhone is warm", "Paused — Low Power Mode").
- **Continue in background (iOS 26):** when the user leaves during a long scan, `BGContinuedProcessingTaskRequest` shows system progress. In-app, a one-time tip (TipKit, `generators/tipkit-generator`) explains "CleanSlate can keep scanning while you use other apps".
- **First run on a big library:** the first groups must appear in under 60 s on a 100k library. The exact-copy buckets come first, since they're cheap.

### Validation and budgets (initial; tune and record the actual numbers)

| Metric | Budget | Where measured |
|---|---|---|
| Metadata inventory, 250k (fake) | ≤ 60 s on Mac-hosted simulator | ScaleTests |
| Peak memory, 250k (fake) | ≤ 300 MB | ScaleTests |
| DB size, 250k | ≤ 150 MB | ScaleTests |
| Planted exact recall | 100% | ScaleTests |
| Planted near-candidate recall (H ≤ 8) | ≥ 99% | ScaleTests |
| Main-thread hangs during scan | none > 250 ms | Instruments Hangs, 10k simulator |
| Kill during inventory → relaunch | resumes, no duplicate rows | manual + test |
| Token expired | full rescan, no crash | test (fake throws 3105) |

- **🧑 HUMAN GATE (device, read-only):** the human runs a **scan-only** pass (no deletion) on their real library in a DEBUG build. Record the item count, total time, Instruments Energy/Time Profiler/Allocations snapshots, and thermal state over time. Scanning only reads, but the human must explicitly agree to run it on a personal library.

### Review focus
Concurrency correctness: no `@unchecked Sendable` without a comment explaining why, no actor reentrancy bugs in `LibraryStore` (state checked again after each `await`), and every SQLite statement finalized. Run `/code-review high` for this step, since it's the riskiest refactor.

### Exit criteria
Full-library coverage with no caps · resume and incremental updates work · budgets met or deviations logged with a plan · the device scan-only report is logged.

---

## Step 6 — Targeted invalidation instead of wipe-all

**Goal:** a library change only affects the groups that contain changed items.

### Tasks
**6.1** Replace `CleaningViewModel.invalidateAfterLibraryChange()` with a path through the store. A change notification → Step 5.4 fetches persistent changes → changed IDs → `UPDATE groups SET state=1 WHERE id IN (SELECT group_id FROM group_members WHERE asset_id IN (...))` → queue only those groups for a recheck.

**6.2 Recheck:** re-snapshot the members. If revisions match the grouping, the group is fresh again. If a member was deleted, the group is dissolved or shrinks (a group needs ≥ 1 keeper and ≥ 1 candidate). If something changed, recompute the evidence for that group only (rehash and feature print), or dissolve it.

**6.3 UI:** stale groups show "Rechecking…" with the Delete button **disabled**. A dissolved group that's open shows "This group changed and was removed" and goes back.

**6.4** The commit-time checks in `PhotoDeletionCoordinator` stay exactly as they are. This step is only about usability, not safety.

**6.5 UX surface: tray revalidation.** When an approved group in the tray goes stale, it's rechecked automatically. If it's still valid, nothing visible changes. If it changed, it moves into a "Needs another look" section at the top of the tray with the reason ("You favorited one of these photos", "A photo was edited", "A photo was already deleted"). A single "Review again" button reopens the group. The tray's Delete button counts only valid items, and the count change animates.

### Validation
- Fake library tests:
  - Changing an unrelated asset leaves every group fresh.
  - Changing a member makes only that group stale.
  - Deleting the keeper dissolves the group.
  - Favoriting a candidate gets it blocked as `.protected` after the recheck.
  - Delete is disabled while stale (view-model level).
- A **property test:** 1,000 random change sequences over 200 assets and 50 groups. Invariant: after processing, no group is fresh while containing a member whose current revision ≠ `revision_at_grouping`.
- Simulator: start a scan, open Photos in the simulator, favorite one fixture photo, and come back. Only that photo's group is rechecked and it now shows as protected; other groups are untouched.

### Exit criteria
The invariant property test passes · manual simulator check logged.

---

## Step 7 — Bursts, similar shots, best-shot review UX

**Goal:** fast, trustworthy culling of bursts and similar shots, with several keepers per group and nothing preselected.

### Tasks

**7.1 Multi-keeper groups**
`PhotoReviewGroup.keeper` becomes `keepers: [PhotoSnapshot]` (Core's `ReviewCluster.keeperIDs` already supports sets). Update `coreCluster`, the views and the coordinator (`keeperIDs = Set(keepers.map(\.id))`). Evidence gets a `visuallySimilar` edge between every candidate and every keeper; `SafetyPolicy` needs a *direct* link from a target to *some* keeper, which is already the behavior.

**7.2 Sequence grouping (Core)**
Add `SequenceGrouping.swift`. Inputs: `(id, time, burstID, featureDistance to neighbors)`. Groups are: the same `burstID`, or consecutive shots ≤ 3 s apart where each adjacent pair has distance < T_seq. Cap each group at 30. This builds **review sets**, never deletion evidence. Test chaining limits: a slow pan across 40 different frames must not become one group (check that the distance between first and last is also < 2·T_seq, otherwise split).

**7.3 Difference warnings (App, shown in the UI, not hard blocks)**
For each candidate and its closest keeper, compute:
- Face count (`DetectFaceRectanglesRequest`).
- Worst-face capture quality.
- Text difference (`RecognizeTextRequest`, checked in SDK; compare normalized text sets).
- Feature-print distance band.

If the face counts differ, the text differs, or the distance is above the "different moment" threshold, show a warning chip ("Different number of people", "Different text"). The user must acknowledge it per photo before that photo can be selected. Don't set `uniqueContentDetected` from these heuristics. That hard block stays for calibrated signals (Step 9).

**7.4 Review UI** (extend the Step 2B review screen and compare mode; don't build a second one)
- **Multi-keeper:** the chosen design must support several Keep photos. A burst of 12 might keep 3. The "Suggested" sparkle badge (`sparkles`) marks the ranker's picks; they start as Keep, all others start *undecided* (U4), and "Approve" stays disabled until at least one photo is marked Delete.
- **Burst helpers:** a "Keep suggested, mark the rest" shortcut button. It marks, it doesn't approve, so the user still sees every photo marked before tapping Approve. Each warning chip on a photo (7.3) must be acknowledged by tapping it before that photo can be marked Delete.
- **Face-crop strip in compare mode:** per-face crops under each photo, aligned by face index, with eyes-closed or blurry faces dimmed and labeled.
- **Undo:** the last 20 actions within a group via the undo toast and shake-to-undo.
- "Mark group reviewed" writes to `reviews` with the member revisions. A reviewed group doesn't come back after a rescan unless a member's revision changed.
- Nothing is preselected in similar or burst groups. Assert this in a test.
- Accessibility: every gesture is also a button and a VoiceOver custom action (U13).

**7.5** Keep `KeeperRanker` as is (it gets tuned in Step 9). Add per-face quality to `QualitySignals` as `minFaceQuality` and `faceCount`. Update the test for the new score ordering and check that missing values still give 0.5.

### Validation
- Core: sequence grouping tests (burst, time chain, anti-chaining split, cap); multi-keeper policy tests (target linked to keeper 2 but not keeper 1 → allowed; target linked to nobody → `.missingProof`).
- UI tests (fake mode):
  - Open a burst group → assert 0 selected → swipe down 2 → acknowledge a warning on 1 → review → `delete` called with exactly 2.
  - Undo restores the selection.
  - A reviewed group doesn't reappear after a rescan.
- `XCUIApplication().performAccessibilityAudit()` passes on the group and compare screens.
- **🧑 HUMAN GATE (device):** cull 3 real bursts on the test device (shoot them on the test phone). Record time per group and any moment where the suggested keeper was clearly wrong. Record a screen capture for the log.

### Exit criteria
Multi-keeper end-to-end · no preselection in similar groups (tested) · accessibility audit passes · device UX notes logged.

---

## Step 8 — Batch deletion with one confirmation, plus album transfer

**Goal:** clear hundreds of verified exact copies in one confirmation, and stop "it's in an album" from blocking legitimate duplicates.

### Tasks

**8.1 `SafetyPolicy.validateBatch` (Core)**
```swift
public static func validateBatch(_ plans: [ApprovedDeletionPlan],
                                 currentByID: [String: AssetRecord]) -> [Int: ReviewReason]  // empty = OK
```
Rules:
- Each plan passes `validateCommit`.
- **No ID is a keeper in one plan and a target in another.**
- No ID is a target twice.
- Total targets ≤ 500.
- Any failure rejects the **whole** batch (fail closed). The UI then offers "Remove the N blocked groups and retry".

Tests: cross-plan keeper conflict; duplicate target; size limit; one stale plan poisons the batch; empty batch.

**8.2 Batch coordinator**
`commitBatch(groups:)`:
1. Fresh snapshots for all involved IDs.
2. `validateBatch`.
3. Rehash every exact target and keeper, with progress, cancellable.
4. Re-snapshot and recheck after the rehash.
5. **One** `performChanges { deleteAssets(all) }`. This gives one Apple confirmation.
6. Reconcile each item and write one receipt.

Cancelling before step 5 deletes nothing.

**8.3 Wire the Step 2B tray to the real batch coordinator**
The "Approve all" sheet, the tray and the `ConfirmSheet` already exist from Step 2B on fake data. Replace the fake call with `commitBatch`. The tray is the batch: each approved group becomes one `ApprovedDeletionPlan`, and standalone items (Step 4) go through `validateStandalone` in the same commit.
- **Progress:** after **Continue** in the `ConfirmSheet`, show "Double-checking 214 photos…" with determinate progress and a Cancel button. This is the rehash step; nothing is deleted yet.
- **Then** Apple's prompt. If anything fails validation, the sheet says what ("2 groups changed since you approved them and were set aside") and offers "Delete the other 212", which builds a new batch and goes through Apple's prompt again. Never delete partially without the user seeing this.
- **Receipt** from Step 2B, now with real numbers (Step 10.1).

**8.3b UX surface: album transfer.** In a group where a copy is in albums the keeper isn't in, show an `EvidenceChip` "In 2 albums". Tapping it shows the album names and one toggle, "Add the kept photo to these albums" (on by default). The tray's `ConfirmSheet` lists "Will add 6 photos to albums first". Without the toggle, that copy stays protected.

**8.4 Album transfer (Core rule change — 🧑 HUMAN GATE)**
- `AssetRecord` gains `userAlbumIDs: Set<String>`: regular user albums only (`assetCollectionSubtype == .albumRegular`).
- `curatedAlbum` moves out of `hard` into a new rule: a target in user albums is deletable only if `target.userAlbumIDs ⊆ keeper.userAlbumIDs`. Shared/cloud albums still give a hard `.shared` flag.
- **Authorized test change:** `testHardFlagsAlwaysBlock` no longer includes `curatedAlbum`. Add `testAlbumMemberBlockedUnlessKeeperInSameAlbums`, `testAlbumMemberAllowedWhenKeeperSuperset` and `testSharedAlbumAlwaysBlocks`. Update `testAllFlagsCovered`.
- App: for blocked album members, offer "Add the kept photo to these N albums first" (only albums where `canPerform(.addContent)`). Run it as a **separate** `performChanges` (adding to albums doesn't prompt), then fetch again to verify membership, then run the normal deletion flow. If the add fails or can't be verified, nothing is deleted.
- Note: album membership must be part of the revision fingerprint (`PhotoCatalog.snapshot`) or checked separately at commit time; otherwise a membership change between review and commit isn't detected. Add it to the fingerprint and add a test.

### Validation
- Core tests above, and the fuzz test from Step 3 extended to batches. Invariant: across a validated batch, no keeper ID is ever in the deletion set.
- Fake library tests:
  - A batch of 50 groups → exactly one `delete` call with 50 IDs.
  - The user cancels the system prompt → 0 deletions, no receipt.
  - A rehash mismatch in group 37 → no deletion at all.
  - Album add fails → no deletion.
  - Album add succeeds → deletion proceeds and the keeper is in the album afterwards.
- Simulator: seed 20 exact pairs → Review all → one system prompt → 20 removed → Recently Deleted shows 20.
- **🧑 HUMAN GATE (device, disposable library):** a batch of 10 exact pairs, 2 of them in a user album with album transfer. Afterwards, check that each album still contains a copy of each photo.

### Exit criteria
One prompt per batch · the cross-group keeper invariant is proven by tests and fuzzing · album transfer approved and checked on device.

---

## Step 9 — Measure accuracy (evaluation harness)

**Goal:** turn "heuristic" into measured numbers. Prove the system never suggests deleting unique moments, and tune best-shot ranking with labeled data. This step **does not** turn on automatic near-duplicate selection unless the statistical gate passes, and it probably won't before launch. That's expected.

### Tasks

**9.1 Pure-Core dHash + eval CLI**
- Move the dHash *math* into Core as `DifferenceHash.compute(gray9x8: [UInt8]) -> UInt64`. The App keeps only the bitmap rendering. Add an executable target `cleanslate-eval` to `Core/Package.swift` (macOS). It reads images with ImageIO behind `#if canImport(ImageIO)`, plus a manifest CSV or JSON, and prints metrics as JSON.
- Metrics:
  - exact recall and precision;
  - near-candidate recall at Hamming thresholds 6/8/10/12;
  - **harmful-suggestion rate** = suggested removals whose label is `unique_*`, with a Clopper-Pearson 95% upper bound from `SafetyStatistics`;
  - best-shot top-1 agreement.
- **CI gate on synthetic fixtures:** every `exact_copy` is found as exact; **0** `unique_text/expression/subject` items reach the Exact tier; `recompressed` and `brightness` are found as near candidates. Add it to `make ci`.

**9.2 On-device labeling mode (DEBUG / TestFlight only)**
- A hidden settings switch (tap the version 7 times) turns on "Label mode". In group review, each candidate gets labels: `redundant` · `unique:people` · `unique:expression` · `unique:text` · `unique:moment` · `unsure`, plus "which one is the best shot".
- Export through the share sheet as JSON with **derived data only**: hashed asset IDs (SHA-256 with a per-export random salt), feature-print distances, dHash distances, quality signals, flags and labels. No images, no localIdentifiers, no locations. A unit test asserts the export schema contains no image data or identifiers.
- Store the evaluation data **outside the repo** (`~/cleanslate-eval/`) and add the path to `.gitignore` for safety.

**9.2b UX surface: Label mode.** Label mode reuses the review screen and adds a compact label picker per photo (a segmented `Menu` with icons). It must not slow down normal review, so it's hidden unless the switch is on. Also add a non-debug, privacy-safe **"This suggestion was wrong"** button to every group (`hand.thumbsdown`). It only stores a local counter and the reason, shown to the user in Settings → "Suggestions you corrected", and is never transmitted. This counter feeds the TestFlight harmful-suggestion reports in Step 10.

**9.3 Independent opportunities**
Sibling frames are not independent. The unit of analysis is **one group = one opportunity**; the harmful rate is counted per group ("did we suggest removing anything labeled unique in this group?"). This is from `DEVICE_TEST_PLAN.md`.

**9.4 Ranker tuning**
Fit `KeeperRanker` weights with a simple pairwise logistic regression on "best shot" labels, implemented in the CLI in pure Swift with no dependencies. Freeze the weights into Core as `KeeperRanker.Weights.v2` with the dataset size and fit date in a comment. Add a regression test that pins the ordering on a frozen synthetic set. Ship v2 only if held-out top-1 agreement beats v1 by ≥ 5 points; otherwise keep v1 and log the result.

**9.5 The automatic-selection gate (decision record)**
Write `docs/ML_GATE.md`. Near-duplicate preselection (`PreselectionConfiguration.nearEnabled && independentSafetyGatePassed`) may only be turned on when the harmful-suggestion upper bound is < 0.1% at 95% confidence on held-out independent groups. That needs ≥ 2,995 groups with 0 failures (`oneSidedUpperBound(0, 2995) ≈ 0.001`). Record the current numbers. The expected outcome for v1 launch is **manual-only**, and the doc should say so.

### Validation
- `swift run --package-path Core cleanslate-eval --manifest /tmp/cleanslate-fixtures/manifest.csv` prints metrics, and the CI gate passes.
- Unit tests for the metric math (known confusion matrices → exact expected values) and for the export schema's privacy.
- **🧑 HUMAN GATE:** the owner labels at least 200 groups from their own library with Label mode, runs the eval, and reviews the report. Also review any group where the suggested keeper was labeled worse than the best.

### Exit criteria
Eval CLI and synthetic CI gate in place · the first real-data report logged · ranker decision (v1 vs v2) recorded · `ML_GATE.md` written.

---

## Step 10 — Release readiness, TestFlight, and the launch gate

**Goal:** something a stranger can install, understand and trust, with every App Store requirement covered.

### Tasks

**10.1 Storage receipts**
After each commit, write a receipt to `receipts`:
- requested, verified removed, uncertain;
- verified logical bytes;
- estimated bytes, labeled;
- free space on the device before and after, from `URLResourceValues.volumeAvailableCapacityForImportantUsage`.

Add a "History" screen. The copy must say: *"Deleted items stay in Recently Deleted for 30 days. Space on the phone and in iCloud is freed after they're removed from there. iCloud savings are an estimate."* Add a "How to empty Recently Deleted" help sheet (text only).

**10.2 Privacy manifest** (`PrivacyInfo.xcprivacy`)
Declare the required-reason APIs actually used: UserDefaults (`NSPrivacyAccessedAPICategoryUserDefaults`), disk space (`NSPrivacyAccessedAPICategoryDiskSpace`) and file timestamps if used. **Check each reason code** against Apple's current "Describing use of required reason API" docs before writing it, and record the URL and access date in the log. `NSPrivacyTracking = false`; collected data types empty. Add `ITSAppUsesNonExemptEncryption = NO` (the app only uses CryptoKit hashing); confirm against Apple's export compliance docs and log the source.

**10.3 Accessibility and localization**
- Dynamic Type up to AX5 on every screen (snapshot at the largest size in a UI test), VoiceOver labels, `performAccessibilityAudit()` on every screen in UI tests.
- Move all strings into a String Catalog (`Localizable.xcstrings`). English only at launch; run the pseudo-language check (Xcode's "Double-Length Pseudolanguage" scheme option) once and fix clipping.

**10.3b Final experience polish pass**
- Run `apple-skills:ios` → `ui-review` (HIG) across every screen, and `apple-skills:design` → game-feel `feedback-audit`: list each event (approve, skip, undo, blocked, scan found first group, scan done, batch deleted) × channels (motion, haptic, text, VoiceOver announcement). Every meaningful event has at least 2 channels, and nothing fires twice.
- Check Liquid Glass compliance (liquid-glass skill checklist): glass only on the navigation layer, no glass on glass, one container per group of glass elements, only primary actions tinted, and correct appearance with Increased Contrast and Reduce Transparency.
- Light, dark, tinted/clear icon appearances for the app icon (iOS 26 icon variants; `generators/app-icon-generator` for the asset layout, while the artwork itself is a 🧑 human decision).
- **Empty and edge states in practice:** library of 0 photos, limited access with 12 photos, a 250k fake library, every photo protected, all originals in iCloud with verification off, airplane mode, and the user revoking access mid-review. Each must show a designed `ContentStateView`, never a blank screen.
- **iPad:** the app targets iPhone only (`TARGETED_DEVICE_FAMILY: 1`), so on iPad it runs in compatibility mode. Keep that for 1.0 and note it in PRODUCT.md.
- **🧑 HUMAN GATE:** a 10-minute hallway test with 2–3 non-technical people on a test device with seeded fake data. Task: "Free up space, but keep anything you care about." Record where they hesitated, and fix the top 3 issues before TestFlight.

**10.4 Assets and metadata**
- 🧑 App icon at 1024×1024 (made or approved by the human; the agent only wires it up).
- Privacy policy and support pages: a `site/` folder published with GitHub Pages (static HTML, no trackers). The policy says no data is collected.
- App Store screenshots made by a UI test in fake-library mode (no real photos), with `fastlane snapshot` or an `XCUIScreenshot` attachment exporter, at the required device sizes.
- App Store description, keywords and promo text in `fastlane/metadata/en-US/`.

**10.5 Identity checks (🧑 HUMAN)**
App name availability in App Store Connect ("CleanSlate" may be taken, so prepare 3 alternatives); register the bundle ID `org.cleanslate.free` (or the human's reverse domain); Apple Developer Program membership active.

**10.6 TestFlight**
- `fastlane beta` with an App Store Connect API key from the environment (never committed).
- Internal testing first (the owner, 1 week), then external Beta App Review with about 20 testers, picked for big libraries (50k+) with iCloud Photos on.
- Testers get a short guide: back up first; start with Exact copies; report anything that looked wrong.
- Use TestFlight's built-in feedback and crash reports and the Xcode Organizer. No third-party SDKs.

**10.7 Launch gate review** (produce `docs/RELEASE_CHECKLIST.md` with evidence links)

| Gate | Required evidence |
|---|---|
| `make ci` green on the release commit | CI run URL |
| All 🧑 device gates from Steps 1, 3, 4, 7, 8 PASS | VALIDATION_LOG entries |
| Scale: 250k harness within budgets; ≥ 1 real library ≥ 50k scanned | Step 5 log |
| Synthetic eval gate: 0 unique items in the Exact tier | CI artifact |
| TestFlight: ≥ 14 days, ≥ 15 active external testers, **0 harmful-deletion reports**, crash-free sessions ≥ 99.5% | ASC screenshot + feedback summary |
| Near-dup preselection | OFF unless `ML_GATE.md` says the gate passed |
| Privacy manifest / export compliance / App Privacy "Data Not Collected" | ASC + sources |
| Accessibility audit passes on all screens | UI test results |
| UX rules U1–U15 each covered by a passing test or a signed-off manual check; HIG ui-review and feedback audit findings resolved | VALIDATION_LOG + `docs/screens/` |
| Hallway test done; top 3 issues fixed | Step 10.3b log |
| Version 1.0.0 (build N) tagged, release notes written | git tag |

**10.8 Submit (🧑 HUMAN only)**
`fastlane store_upload_only` uploads the build and **does not** submit. The human submits for review in App Store Connect, picks manual release, and releases after approval.

### Validation
- `make ci` green, plus the full UI test suite with the accessibility audits.
- Receipts: fake tests check that before/after free space is recorded and that verified and estimated bytes are never added together. A UI test checks that the History copy contains the Recently Deleted note.
- 🧑 The full device test plan re-run on the release candidate build from TestFlight, not a debug build.

### Exit criteria
Every row of the launch gate table has evidence · the human submits.

---

## Appendix A — Dependency map

```
1 (baseline, seams) ─► 2 (scope, iOS 26) ─► 2B (design system + Review→Approve→Tray on fake data)
                                              │
                                              ▼
                      3 (exact v2) ─► 4 (media types) ─► 5 (scale engine)
                                                                         │
                                         6 (targeted invalidation) ◄─────┘
                                         7 (burst UX)  ── needs 5's store for reviews
                                         8 (batch + albums) ── needs 3's flag split
                                         9 (eval) ── needs 7's labeling surface
                                        10 (release) ── needs all
```
Steps 6, 7 and 8 can be reordered among themselves if the human asks, but all of them need Step 5.

## Appendix B — Files likely touched per step

| Step | Core | App | Tests / other |
|---|---|---|---|
| 1 | – | `VisualFeatures`, new `PhotoLibraryClient`, `PhotoDeletionCoordinator`, `CleaningViewModel` | `iOSTests/Fakes/*`, `DeletionCoordinatorTests`, Makefile, CI, `.gitignore` |
| 2 | – | `DashboardView`, new `Onboarding*`, `App/Debug/*` | UI test target, `docs/PRODUCT.md` |
| 2B | – | `App/DesignSystem/*` (tokens, components, `HapticsService`), new Home/Inbox/Review/Compare/Tray/Receipt views, approvals store | snapshot + UI tests, `.swiftlint.yml`, `docs/design/PROTOTYPE.md`, `docs/design/WORD_LIST.md` |
| 3 | `ExactCandidates`, `Models` (flags), `SafetyPolicy` | PhotoKit client, Settings, `NetworkPolicy` | `SafetyPolicyTests` (authorized split), `ExactMatchingTests` |
| 4 | `SafetyPolicy.validateStandalone`, `Models` | inventory, video sampler, 3 new category views | video fixtures script |
| 5 | `CandidateIndex` (band queries) | `Store/LibraryStore`, `ScanEngine`, background tasks, `project.yml` | `ScaleTests`, bulk seed script |
| 6 | – | store invalidation, view-model | property test |
| 7 | `SequenceGrouping`, `KeeperRanker` | review views, compare view, `reviews` table | UI tests, accessibility audit |
| 8 | `validateBatch`, album rule | batch coordinator, Review All, album transfer | fuzz + fake tests |
| 9 | `DifferenceHash`, `cleanslate-eval` target | Label mode, export | eval CI gate, `docs/ML_GATE.md` |
| 10 | – | receipts/History, strings catalog, privacy manifest | `site/`, fastlane metadata, `RELEASE_CHECKLIST.md` |

## Appendix C — Verified facts this plan relies on (iOS 26.5 SDK, Xcode 26.6, checked 2026-11-05)

- `PHPhotoLibrary.currentChangeToken`, `fetchPersistentChangesSinceToken:error:` — iOS 16+. `PHPhotosErrorPersistentChangeTokenExpired = 3105`.
- `PHAssetMediaSubtype`: `PhotoScreenshot`, `PhotoLive`, `VideoScreenRecording` (iOS 13+), `VideoCinematic`, `SpatialMedia`.
- `BGContinuedProcessingTaskRequest initWithIdentifier:title:subtitle:` — iOS 26+, wildcard identifier required.
- Vision Swift API: `GenerateImageFeaturePrintRequest`, `CalculateImageAestheticsScoresRequest`, `DetectFaceCaptureQualityRequest`, `RecognizeTextRequest`. `FeaturePrintObservation.distance(to:) throws -> Double`. `FeaturePrintObservation: Codable`.
- Liquid Glass (SwiftUICore, iOS 26): `glassEffect(_:in:)`, `GlassEffectContainer`, `glassEffectTransition`, `.glassProminent` button style. Also `sensoryFeedback`, `ContentUnavailableView`, and `XCUIApplication.performAccessibilityAudit` (XCUIAutomation).
- **Not yet verified, check before relying on it:** privacy-manifest reason codes (Step 10.2), export-compliance exemption wording (10.2), the exact location of the Photos Duplicates album on current iOS (Step 2.3), and whether the simulator Vision failure is a hardware limitation (Step 1.2).
