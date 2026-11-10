# F10: Step-10 completion (accessibility, localization, HIG polish, panel review)

## Goal and story
*Anyone, including VoiceOver users, people using the largest text and people on small older phones, can understand
and use every screen, and every word is ready for translation.* This finishes `EXECUTION_PLAN.md` Step 10.3/10.3b
across the original screens **and** everything F01–F09 added, then runs the launch-gate review (10.7) up to the human gates.

## Trust / privacy / safety
Polish must not change behaviour. Any copy change on deletion surfaces (confirm sheet, tray, receipt, the
How-deleting-works sheet) keeps the Recently Deleted and "Apple asks you to confirm" statements word-for-word unless
the owner approves a change. The U1–U15 tests stay green.

## Device tier
Verify layouts on the **iPhone SE (3rd gen) simulator (4.7", SE-test)** first, then a 6.1" model. AX5 on SE is the
hardest case. Snapshot images are produced by UI tests only, so no runtime cost.

## Screen inventory (each gets an audit, AX5, dark-mode and SE screenshots)
Onboarding (5 pages) · Home (idle / scanning / paused / stalled / finished / limited / denied) · Quick Start card ·
Scope picker (+ month, album lists) · Category groups · Review group · Compare · Standalone list · Approve all ·
Tray · Confirm sheet · Receipt · History · iCloud originals sheet · Diagnostics · Your privacy · Data on this iPhone ·
How deleting works · How to get photos back · Impact · Activity · Coverage · Check more · Kept safe.

## Files
| Action | Path |
|---|---|
| create | `UITests/AccessibilityAuditUITests.swift`: one test per screen: navigate (fake library, launch arguments), `try app.performAccessibilityAudit(for: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .trait, .dynamicType, .textClipped])` (all 7 members verified in the installed XCTest headers; `.action` and `.parentChild` also exist and may be added), then again with `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` |
| modify | `UITests/ScreenshotTests.swift`: the screen inventory × {light, dark, AX3} × {SE-test, default} into `docs/screens/F10/` |
| modify | `App/Resources/Localizable.xcstrings`: all user-facing strings; plural variations for counts ("%lld photos") |
| modify | `project.yml`: `SWIFT_EMIT_LOC_STRINGS: YES` and `LOCALIZATION_PREFERS_STRING_CATALOGS: YES` (both settings verified in the installed Xcode's CoreBuildSystem.xcspec) |
| modify | Views/services with `String` interpolations built outside SwiftUI (`CleaningViewModel.finishScan` messages, `ResourceGovernor` reasons, `DeletionTray` toasts): use `String(localized:)` with comments |
| modify | any view failing the audits (fixes only) |
| create | `docs/design/PANEL_REVIEW_10.md`, `docs/design/FEEDBACK_AUDIT.md` |
| modify | `docs/RELEASE_CHECKLIST.md`, `docs/ARCHITECTURE.md` (scopes, stability, diagnostics, activity), `docs/PRODUCT.md` (scope-first positioning, device floor) |

## Sub-tasks
1. **String extraction**: enable the settings, build, and move every literal into the catalog with translator comments.
   Fix concatenated sentences into single format strings. Plurals via catalog variations. A test asserts that
   `Localizable.xcstrings` has no entries in state `new`/`stale` (parse the JSON).
2. **Pseudo-language pass**: run the UI screenshot suite with the double-length pseudolanguage (Xcode scheme option;
   the equivalent launch argument is UNVERIFIED and must be checked). Fix clipping and truncation. Log the before/after screenshots.
3. **Accessibility audits** on every screen above; fix findings (labels, traits, hit regions ≥ 44 pt, contrast in both
   modes, Increase Contrast and Reduce Transparency appearance of glass bars).
4. **VoiceOver flows**: custom actions Keep / Delete / Compare on photo tiles (U13) are verified on the review and
   compare screens. Announcements: "first group found", "scan finished", "paused", "stalled" (F05), "deleted N photos".
5. **HIG / Liquid Glass pass** (`apple-skills:ios` ui-review + `apple-skills:design` liquid-glass checklist): glass only
   on bars, the approval bar, toolbars and tray button; one `GlassEffectContainer` per cluster; only primary actions
   tinted; no glass on lists, cards or progress cards.
6. **Feedback audit** (`FEEDBACK_AUDIT.md`): events × channels (motion, haptic, text, VoiceOver) for approve, skip,
   undo, blocked, first group found, scan paused, stalled, scan done, batch deleted, prompt declined. Each event has
   ≥ 2 channels and nothing fires twice.
7. **Edge states** (10.3b): 0 photos, limited with 12, 250k fake, all protected, all iCloud-only with verification off,
   airplane mode, access revoked mid-review, stalled scan. Each shows a designed `ContentStateView`.
8. **Panel review** (`PANEL_REVIEW_10.md`): personas = safety architect, iOS/HIG designer, privacy/App Review,
   performance (low-end), first-time cautious user on an SE. Record each finding → decision → commit.
9. **Release checklist update**: mark what is now evidenced; leave device, TestFlight, icon, legal and identity as 🧑.

## Acceptance criteria
- `AccessibilityAuditUITests` pass for every screen at default size and AX5, on SE-test and the default simulator.
- No catalog entries are `new`/`stale`; no user-facing literal outside the catalog (a lint script greps for
  `Text("` with interpolated `String` variables flagged; it is allowed only for catalog keys).
- Screenshots exist for the inventory in `docs/screens/F10/`. The pseudolanguage pass has no clipped text (manual check, logged).
- The feedback audit table is complete; the panel review has every blocking finding fixed or explicitly deferred by the owner.
- `make ci` + `make budget` green; U1–U15 coverage table updated in `VALIDATION_LOG.md`.

## Test plan / validator checklist
Run the audits in dark mode, Increase Contrast and Reduce Motion (launch arguments or simulator settings). Run VoiceOver
by hand through Quick Start → Review → Approve → Tray → Delete (fake) → Receipt → Impact (validator records it). Check that
no layout scrolls horizontally at AX5 on the SE. Regression: every earlier UI test still passes.

## Privacy review
None new. Re-confirm the privacy-manifest reason codes and export compliance against Apple's pages (still UNVERIFIED in the checklist; 🧑/planner web check).

## Rollback
String-catalog migration is mechanical; revert per screen if a regression appears.

## Dependencies
F01–F09 complete. This is the last feature before TestFlight.

## Definition of done
All the above, plus 🧑 hallway test (Step 10.3b) with 2–3 non-technical people on an SE-class device with seeded fake
data: task "Free up space, but keep anything you care about". Fix the top 3 issues. Gatekeeper APPROVE on the final
diff; the release checklist is honest.
