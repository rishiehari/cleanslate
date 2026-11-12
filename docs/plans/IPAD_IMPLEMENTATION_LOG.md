# iPad implementation evidence

## 2026-11-12 — universal target and adaptive review workspace

Implemented a universal iPhone/iPad target with explicit single-window support and four iPad orientations. Compare reuses the existing shared zoom/pan and bounded 1,400-pixel thumbnails in equal side-by-side panes when width permits. Narrow windows and accessibility text stack the panes.

ReviewSessionView now keeps its active review in the same structural position while a contextual queue appears alongside it in wide windows. It reuses GroupRowView, highlights the current group, scrolls to the next group after Approve/Skip, and explains unavailable groups. The queue is read-only in this increment; direct queue selection and draft restoration across destination changes remain pending. Resizing never creates another tray, coordinator or scan service. Empty session input has a designed state rather than indexing an empty array.

Standalone screenshots use an adaptive grid rather than three fixed columns, with larger minimum tiles at accessibility text sizes. Selection remains in the existing view state. No select-all option was added to large files.

Validation runs use an isolated worktree based on 2e03c99 with only the owned iPad files copied in. This verifies the increment independently of concurrent large-library work; it does not establish that the combined shared working tree builds. The shared build currently fails because App/Tests/ScanScopeTests.swift imports XCTest into the application target; earlier scope API compile errors are also recorded in VALIDATION_LOG.md. Other agents' files have not been reverted or repaired here.

- Isolated generic simulator build: PASS (arm64 and x86_64).
- Isolated Core: 115 tests PASS.
- Lint/policy separation: PASS.
- Four focused layout-policy unit tests: PASS on iPhone 17 Pro simulator (iOS 26.5).
- Two existing iPhone review-flow UI tests: PASS (exact approval adds only to tray; approval/skip advances the review session).
- iPad mini rotation/queue test: BLOCKED before any test case started, including a separate UI-only retry. Screenshot shows the simulator stuck at Apple boot progress; bootstatus also did not complete. Runs stopped rather than reported as passing. Test remains in the repository for rerun on a healthy iPad simulator.
- Physical device gates, full iOS/budget matrix, AX5/contrast/VoiceOver and full shell migration remain pending. Provisional layout widths are design tokens, not device compatibility claims.

SDK evidence: iPhoneSimulator27.2 SwiftUI interface exposes ScrollViewReader/scrollTo at lines 25047–25080; sidebarAdaptable at 9488. The installed session has no apple-skills package; existing design-system components and SDK declarations are used.
