# Native iPad app plan

Date: 2026-11-11. Status: implementation started by owner request on 2026-11-11; release remains gated. The implementation target is universal (`TARGETED_DEVICE_FAMILY = 1,2`), iOS 26 minimum. This plan proposes a universal app, retaining the same bundle ID and shared engine, after the owner authorizes implementation. Existing device gates remain PENDING.

## Product outcome and boundaries

Make the larger display useful for deciding which memories to keep: readable side-by-side photos, a persistent review queue, quick movement between groups, and an understandable tray. An enlarged iPhone canvas alone does not meet the requirement.

Primary jobs:

1. Compare two close shots comfortably, including faces and small details, without losing context.
2. Work through an exact-copy inbox or a larger burst with several keepers.
3. Spend a few minutes in Swipe n Save using touch, pointer, keyboard or accessibility actions.
4. Inspect approved deletions alongside the photos staying in the library, then explicitly confirm through the existing tray.
5. See scan progress and pause it while continuing to review available results.

The initial iPad release has feature parity with completed iPhone features. It does not introduce accounts, cloud sync of CleanSlate state, imported external libraries, simultaneous independent scans, automatic deletion, Apple Pencil drawing, a Mac app, or new ML models. The existing opt-in, budgeted PhotoKit download path stays unchanged. Similar-video comparison is still deferred.

The old PRODUCT.md non-goal, “no iPad-optimized layout in 1.0,” is superseded only when an iPad implementation/release is approved; leave it accurate until then. The original roadmap and F03 device gate still apply. iPad planning does not authorize F04–F10 implementation out of order.

## Requirements and defaults

| ID | Requirement | Default and rationale |
|---|---|---|
| IP01 | Same photo-safety contract everywhere | Review → Approve → Tray → Delete → Apple prompt. Bigger layouts never bypass a stage. |
| IP02 | Adaptive navigation | Compact windows use the phone navigation; wide windows use sidebar/list/detail. Preserve destination and draft when switching. |
| IP03 | Useful comparison space | Two equally sized, aspect-fit previews, synchronized zoom/pan, explicit Keep/Delete/Protected labels; full-screen inspection available. |
| IP04 | Same features, appropriate presentation | Existing categories, standalone lists, tray, history, diagnostics and iCloud settings remain available. Planned screens stay planned. |
| IP05 | Resizable window support | Respond to actual window geometry and Dynamic Type, not device names or portrait/landscape alone. No forced full-screen workaround. |
| IP06 | Input parity | Every swipe and keyboard shortcut has a visible button and accessible action. Pointer hover never changes a decision. |
| IP07 | One mutation owner | App-level scan service, tray, store and deletion coordinator; never instantiate an independent coordinator per detail screen. |
| IP08 | Bounded photo work | Keep F03's one-asset scan concurrency and tier budgets. Large windows do not multiply scan workers. |
| IP09 | Honest permissions and storage | Limited access stays limited; verified bytes, unknown bytes and measured free space remain separate. |
| IP10 | Device evidence before release | Simulator layouts cannot validate PhotoKit prompts, Vision, memory pressure, background continuation or the original device hang. |

## Navigation and layouts

Use a shared `AppDestination` value and a navigation state model rather than encoding navigation in view-local booleans. Proposed primary destinations: Home, Swipe n Save, Review categories, Tray, History, Settings. Diagnostics remains a Settings destination. Impact, Activity, Coverage and Kept safe are added only when their roadmap features are implemented.

Recommended shell: compact `TabView`/`NavigationStack`; expanded `NavigationSplitView` with sidebar and detail. A category detail can contain its group list plus review panel when space allows. Avoid nesting two permanent sidebars. A system `.sidebarAdaptable` tab style is a supported alternative, but mixing it with a second category sidebar can waste comparison space. Prototype both, choose the arrangement with one clear navigation hierarchy, and keep destination state independent of the container.

Layout policy uses design tokens for minimum useful photo width, minimum list width and readable text width. Determine token values with prototypes; do not freeze speculative breakpoints into product requirements. Suggested behavior:

| Available space | Presentation |
|---|---|
| Narrow, or accessibility text requires it | One column; category list pushes review; controls stack; keep logical Left/Right names in Swipe n Save even if photos stack. |
| Medium | Sidebar can collapse; two-photo detail gets priority over a permanent inbox; tray and settings use appropriately sized sheets. |
| Wide | Sidebar + group queue + review detail, if both photos remain large enough; otherwise collapse the queue. |
| Very wide | Cap readable text width and useful image sizes; use spare space for context, not giant text or stretched controls. |

No empty detail dead end: show “Choose a group to review” with a visible list selection. Auto-advance after approval preserves the list’s scroll position and selects the next live group. Changes/removals show a reason rather than silently displaying stale photos. Scanning, empty, unavailable, denied, restricted and error states use `ContentStateView` in the relevant pane.

Feature fit:

| Feature | iPad adaptation | Dependency/status |
|---|---|---|
| Exact groups / Approve all | Dense readable queue with verified bytes; full group detail; bulk review sheet with clear exclusions | Exists |
| Similar/bursts | Large comparison and a wrapping thumbnail strip/grid; several keepers; warnings beside the affected photo | Exists; device Vision gate pending |
| Swipe n Save | Centered two-photo workspace, visible three-way choice row, optional queue context | Minimal V1 in progress; expanded plan in SWIPE_N_SAVE_PLAN.md |
| Screenshots / large files | Adaptive grid/list; selection summary stays visible; large-files select-all remains absent | Exists |
| Tray / confirm / receipt | Keeper context and removals side by side; readable confirmation sheet; single presentation owner | Exists |
| History / diagnostics | List/detail where useful, otherwise bounded-width list; user-initiated export only | Exists |
| Quick Start / scopes / progress | Compact persistent progress area; scope picker with adequate room for dates/albums | F04/F05 planned |
| Trust / data inventory | Bounded-width reading; no mandatory extra iPad-only onboarding | F06 planned |
| Impact / activity / coverage / kept safe | More room for lists and explanations, no new data collection | F07–F09 planned |

## Window lifecycle and state

First native release: support one resizable application window; defer multiple simultaneous CleanSlate windows until an explicit concurrency phase. Resizing/windowing is distinct from multiwindow support. Do not promise support for specific Stage Manager configurations or device models without device verification.

Keep application services outside adaptive view branches. Scene-owned state contains selected destination, navigation path, scroll anchors, current pair and unapproved draft. App-owned state contains the tray, scan, index, library change subscription and commit lock. Resizing, switching tabs or opening a sheet must not recreate these services, restart a scan, clear selection, or resubmit an approval.

Persistence restores intent, never authority: serialize photo IDs plus member revisions and choice, not images or acknowledged safety conclusions. On restoration, re-resolve the pair, invalidate stale drafts, rerun warning analysis, and revalidate approved entries with the existing tray checker. Persisted tray entries already exist and must survive the shell migration without a schema break.

Future multiwindow phase requires an app-wide review reservation and deletion lock, one scan, one mutation coordinator, synchronized tray updates, and receipt delivery only to the initiating scene. Another window cannot approve a photo kept/deleted by a pending decision. Closing a window releases its reservations, not committed tray entries. No multiple-window capability should be enabled until these tests pass.

## Touch, keyboard, pointer and accessibility

- Keep photo review gestures on the photo/deck surface, away from navigation edges, toolbar controls and scrolling lists. Zoomed photos consume pan gestures; they must not trigger swipe decisions.
- Pointer interaction uses system button/list semantics and optional hover feedback. Right-click may offer Compare/Keep/Skip but never a direct deletion action.
- Proposed focused-review shortcuts: Left/Right choose the corresponding keeper, Up keeps both in Swipe n Save, Escape cancels the current sheet/choice, Command-Z undoes the local action. Only active review handles these keys. Text fields, menus, sheets and assistive navigation take precedence. Ignore key repeats for decisions.
- Approval remains an explicit labeled button. Do not globally bind Delete, Backspace or Return to photo deletion; normal keyboard activation of the focused button is sufficient.
- VoiceOver reads position, decision, protection reason and verified size where known. Expose named actions for Keep left, Keep right, Keep both, Compare and Approve with the same model guards as touch.
- Support AX5, Switch Control, Full Keyboard Access, Reduce Motion, Increased Contrast and Reduce Transparency. Touch targets remain at least 44×44 points. Do not rely on haptics, color, hover or animation as the sole signal.
- Pencil works as pointing input; drawing/scribble-specific product features are out of scope.

## Performance and PhotoKit constraints

Thumbnail requests should be sized for the displayed rectangle and display scale, with explicit maximum decode dimensions. Never request a full-resolution original merely because the window is wide. Keep only the current pair and a bounded next-pair prefetch; cancel requests on pair change and memory pressure. In Compare, load higher resolution on deliberate zoom and evict when leaving. Preserve local-only image requests and the opt-in original-download boundary.

Use the current device memory tier, not an “iPad means fast” assumption. Provisional acceptance: scan peak remains within the existing tier budget; combined review + scan peak also must fit that budget or the review cache must shrink. Record separate review-only and combined workloads. Keep retained-growth and transient-peak measurements distinct; F03's ≤15 MB metric is marginal settled retained footprint, not peak-to-peak growth. Three repeated review/scan sessions must not grow retained memory by more than the existing 10 MB soak threshold.

Existing residual: `PhotoKitLibraryClient` and inventory snapshots remain main-actor isolated and enumerate resources. The fake watchdog tests do not resolve the actual device metadata-fetch hang described in HANG_RCA_DEVICE_LOG.md. Do not label this “fixed on iPad.” Profile it on the device; any service refactor must be its own scoped, reviewed change.

The app sees the iPad's authorized PhotoKit library, which can differ from the iPhone's, especially with iCloud Photos off. Do not promise it controls an iPhone library or transfers CleanSlate reviews between devices. iCloud Photos may synchronize deletions through Apple's service; the existing cross-device warning remains. Measured free space is local to this iPad and is distinct from verified logical file bytes and any iCloud estimate. Authorization can change while a window stays open; refresh on activation and library change. Never treat disappearance under limited access as verified deletion. System prompts must originate from the active scene; verify sheet/popover/share presentation on iPad rather than assuming phone behavior transfers unchanged.

Privacy: store no image bytes in restoration state, keep caches/identifiers protected and excluded from backup, no cross-window diagnostics with photo IDs, and no new network/export path. Haptics may be unavailable; visual and spoken feedback carry the result.

## Implementation phases and concrete code map

Each phase uses the repository's planner → executor → validator → gatekeeper workflow and commits buildable subtasks. Read required Apple skills before changing views; run SDK checks again on the implementation SDK.

| Phase | Changes | Exit evidence |
|---|---|---|
| IP0: requirements and prototypes | This plan; add adaptive previews under App/Debug when implementation is authorized; choose navigation/width tokens | Review 2-up, 12-photo burst, protected, unavailable and AX5 variants; owner reviews product defaults |
| IP1: universal target and shell | `project.yml` target family 1,2; `CleanSlateApp`; future `AppNavigationModel`, `AdaptiveAppShell`; extract nested stacks from `DashboardView`/destinations as needed | Generated app supports both families; phone suite unchanged; all destinations reachable on compact/wide windows |
| IP2: review layouts | `ReviewGroupView`, `ReviewSessionView`, `CompareView`, `PhotoThumbnailView`, new swipe views, design-system layout tokens | Rotation/resizing preserves selection; compare gestures work; visible keepers and protected reasons everywhere |
| IP3: secondary screens and presentation | `CategoryGroupsView`, `StandaloneListView`, `TrayView`, `ApproveAllSheet`, `ReceiptView`, `HistoryView`, `DiagnosticsView`, onboarding/iCloud sheets | Complete fake flow through one confirmation owner; canceled prompts preserve tray; no duplicate receipts |
| IP4: input and performance | Shared review commands; focus/keyboard/pointer behavior; bounded thumbnail loader/cache; accessibility fixes | Input parity, key-repeat resistance, accessibility audit, measured review+scan budget |
| IP5: release verification | iPad UI tests/screenshots, PRODUCT/ARCHITECTURE/checklist updates, verified metadata/assets | Full simulator gates and owner iPad device evidence; unresolved release gates still block publication |
| IP6: optional multiwindow | Scene restoration and app-level reservations/commit presentation | Adversarial two-window tests; owner scope decision before implementation |

Do not add dependencies or change `SafetyPolicy`, preservation flags, batch limits, the single `deleteAssets` call site, or existing safety assertions for this migration. If a discovered requirement needs such a change, isolate it and follow the existing owner gate. F04–F10 features integrate when ready; they are not prerequisites to make the current screens adaptive.

## Validation matrix and acceptance

Use fake/synthetic libraries for all agent testing. Test a small iPad simulator, a medium one and a large one available in the installed runtime, plus the existing smallest supported phone simulator. Concrete model/OS compatibility is verified at implementation time.

Required configurations: portrait/landscape, full screen and several narrow/intermediate window widths, default/AX3/AX5 text, light/dark, Reduce Motion, contrast/transparency settings, touch, keyboard and pointer. A screenshot alone is not a functional pass.

1. Approve exact/similar/standalone items → tray count changes, `deleteCalls == 0`; opening or resizing any pane never changes that.
2. Tray confirmation cancel and Apple-prompt cancel leave photos intact; successful fake deletion removes only approved targets; keepers/protected photos survive.
3. Change revision/favorite/album status, revoke permission, remove keeper, or edit from another observer between selection and commit: the existing revalidation blocks safely.
4. Resize during marking, comparison, warning sheet, rehash progress, receipt and scan; retain route and valid draft, no duplicated operation, no offscreen primary control.
5. All gestures have working button and VoiceOver equivalents; keyboard commands do not fire in inactive panes, sheets or text fields; repeated keys do not approve multiple pairs.
6. First pair/next pair never becomes a blank unexplained tile; unavailable images show a designed state. Preview latency targets are measured on fixture data, then set from device evidence rather than advertised in advance.
7. Scan + review stay within the tier memory budget; cancellation meets existing scan ≤2 s expectation on fakes; compare caches release; watchdog reports no new >250 ms block attributable to the UI implementation.
8. Accessibility audit every changed screen at default and AX5, screenshots light/dark/AX3, manual VoiceOver route through review and tray.
9. Run `make core-test`, fixtures/eval/lint/build, full `make ios-test`, and budget suites. Report hangs/skips honestly. Release build excludes fake data.
10. Owner device gate: real iPad with disposable library, Photos authorization permutations, local/iCloud-unavailable media, actual Apple prompt, Vision, background/foreground, window resizing, keyboard/pointer and Instruments. Existing iPhone gates remain separate and pending until completed.

## Apple API evidence and unresolved checks

Verified 2026-11-11 against installed `iPhoneSimulator27.2.sdk`; deployment target remains 26. Evidence root: `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator27.2.sdk/System/Library/Frameworks/`.

| API | Local source and finding |
|---|---|
| `NavigationSplitView` | SwiftUI/Modules/SwiftUI.swiftmodule/arm64-apple-ios-simulator.swiftinterface:27120–27153; iOS 16+, two/three-column initializers, visibility binding; preferred compact column iOS 17+ |
| `.sidebarAdaptable` | Same interface:9485–9504; iOS 18+ |
| `TabView`, `WindowGroup` | Same interface:3389 and 2688; public declarations present |
| `ViewThatFits`, `MagnifyGesture`, `DragGesture` | Same interface:14510, 12326, 4787; public declarations present; use existing deployment-compatible APIs |
| `onKeyPress` | Same interface:25324–25336; iOS 17+, explicit key phases available |
| `keyboardShortcut`, named accessibility actions | Same interface:26973 and 252–286; public modifiers present |
| Hover effects | SwiftUICore/Modules/SwiftUICore.swiftmodule/arm64-apple-ios-simulator.swiftinterface:2253–2282; public system modifiers present |
| Photos read-write/limited access | Photos/Headers/PHPhotoLibrary.h:28–33,73–74; scoped authorization APIs iOS 14+ |
| Limited-library picker | PhotosUI/Headers/PHPhotoLibrary+PhotosUISupport.h:35,45; completion-handler variant iOS 15+ |

SDK presence is not device behavior evidence. Generated target-family settings, supported orientations, scene manifest/multiple-window configuration, iPad window constraints, current supported hardware and App Store screenshot requirements must be verified during implementation. No current hardware compatibility or App Store policy claim is inferred from this plan.

Default decisions requiring no extra design work: universal app, iOS/iPadOS 26 baseline, one resizable window first, same engine/safety policy, touch-first with keyboard parity, no cross-device app-state sync. Owner decisions before release: whether iPad ships with the next version, target device test matrix, and whether multiwindow belongs in a later release.


## Implementation increment 1 — 2026-11-11

Owner authorized implementation in the working session. Foundation changes:

- Universal generated target; explicit single-window scene manifest and all four iPad orientations. No full-screen requirement.
- Chose the plan's supported `.sidebarAdaptable` alternative for the first shell increment. A typed scene-local `AppDestination` selection and one stable `TabView` preserve the existing review entrances, app-owned services and sole receipt presenter without geometry-based root replacement.
- Existing Home and Swipe n Save remain the navigation entrances. Category review, tray, history and settings reuse their current routes. Dedicated destination routing and persistent group queue remain outstanding IP1/IP2 work; this is not full shell acceptance.
- Compare reuses its shared zoom/pan and bounded thumbnail request, with equal horizontal panes once both meet the provisional 300-point minimum; narrow/AX layouts stack. `AnyLayout` keeps pane identity across resize. Home content is capped at 760 points.
- Added layout-policy unit cases and a fake-only iPad rotation/choice-safety UI scenario. These new tests require a successful app build before execution can be claimed.

Validation: `make core-test` passed 115 tests; `make lint` passed. `make build` failed on pre-existing working-tree changes: `PhotoModels.swift` references `Color` without importing SwiftUI; `ScanEngine.swift` passes `ScanScope` where diagnostics require `DiagScope`, and passes a scope argument to the existing no-argument `fullInventory`. These were not changed by this increment. Simulator UI tests, screenshots, memory measurements and device evidence remain pending. Installed SDK confirms `.sidebarAdaptable` in SwiftUI.swiftinterface at line 9488. No Apple-specific skills are installed in the session's skill catalog; local SDK verification and existing design-system components were used.

Next buildable increments: complete shared destination routing and onboarding presentation ownership; prototype queue/detail with valid draft retention; adapt group/standalone/tray layouts; focused input and cache work; run the complete IP5 matrix. No claim of production-ready iPad support or resolved F03 gates.


## 2026-11-12 continuation

Universal target/Compare foundations and a contextual persistent review queue are implemented, with adaptive standalone grids. See [implementation evidence](IPAD_IMPLEMENTATION_LOG.md) for isolated build/tests and shared integration blockers. Queue selection is deliberately not implemented in this increment; current review state survives queue visibility changes. Dedicated routing, cross-destination drafts, secondary presentation and full input/performance validation remain open.
