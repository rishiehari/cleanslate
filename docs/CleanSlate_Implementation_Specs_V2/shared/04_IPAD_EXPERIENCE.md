# iPad-specific implementation contract

**Current repo:** `project.yml` already targets iPhone and iPad (`1,2`) and disables multiple scenes; `docs/plans/IPAD_IMPLEMENTATION_LOG.md` reports partial adaptive review layout and a blocked iPad simulator test. This document describes the full tablet feature-level contract and does **not** claim that these layouts are already released.

## Adaptive composition

The iPad must use actual available window width and Dynamic Type environment, not `UIDevice.userInterfaceIdiom` alone. Proposed container: `NavigationSplitView` (sidebar + category queue + detail), collapsing to a phone-like `NavigationStack` for narrow Stage Manager windows. Do not nest multiple permanent split views. The UI may show three panes only when each photo can meet the minimum useful comparison width; otherwise collapse the queue. Preserve selected feature, queue item, zoom, compare mode, and unapproved draft through resize/rotate.

Suggested layout *behavioral bands* (calibrate with screenshots, not hardcoded policy):

- **Compact window:** one-column, photo-first, bottom/toolbar actions; full parity with iPhone.
- **Medium:** collapsible categories sidebar, main review with contextual queue sheet/popover.
- **Wide:** persistent category sidebar, review queue, double-image synchronized comparison; right-side details drawer optional.
- **Large text/AX5:** collapse the queue even on a wide iPad if two image panes would become too narrow; avoid clipping labels.

Multiwindow is **not** available in current project. Do not promise it. If a later phase enables multiple windows, introduce a single app-global actor for scan, tray and PhotoKit mutation; scene-local navigation alone may be duplicated. Two windows must not independently approve opposing keeper choices or submit a delete transaction.

## Tablet interaction essentials

- Touch: native gestures restricted to review canvas, not drag within sidebar.
- Keyboard: focused review can map Left / Right to keeper selection, Up to Keep both, Space to pause/resume, Escape to dismiss choice, Command-Z to undo a staged action. These are *suggested bindings*; final shortcuts need conflict/accessibility review. `Delete`/Backspace must never immediately delete a Photos asset.
- Pointer: hover is visual affordance only, never changes selection or approval; right-click can open Compare, Protect, Skip, not Delete.
- Drag and drop: Album Inbox may allow Photos IDs only as local opaque transfer objects; drop targets are visually and semantically labeled. No drag-to-trash shortcut around the tray.
- Zoom: synchronized side-by-side pan/zoom for comparison with an explicit unlink control; large images fetched only on deliberate zoom, bounded/cancelled.
- Apple Pencil: behaves as a pointer/touch; drawing/stylus-specific annotation features are non-goals.

## Tablet navigation by feature family

- **Storage Goal:** category queue on left, goal summary and evidence in center, selected group comparison on right.
- **Moment/Video:** filmstrip and group list on left, side-by-side image/filmstrip in detail, keeper set and protections persistent.
- **Screenshots:** categories/filters sidebar, OCR-safe group grid, enlarged comparison with changed-text highlighting only while actively displayed.
- **Compression:** job list + Before/After preview + inspector of verified quality/bytes; split view must never imply Photos original already deleted.
- **Album Inbox:** albums sidebar, current inbox grid, selected photo detail; keyboard, pointer and VoiceOver equivalents to drag-and-drop.
- **Rescue Gems:** photo mosaic in detail, date/album sidebar, favorite actions; no intrusive animation.
- **Local Taste:** preference examples with a sidebar for controls and reset, not an opaque "AI settings" screen.
- **Protection Rules:** filterable rules list and live coverage inspector; a rule editing panel must not turn into a global destructive shortcut.

## Persistence, focus and identity

Display scene state (selection, search, zoom) is separate from domain state (scan, protected rules, approved deletion tray). On navigation back or resize, don't create new long-running tasks. Revalidate restored `asset_id+revision` before showing a destructive draft. Keyboard shortcuts only operate in a focus-scoped review scene, never while editing a text field, dismissing a sheet or using VoiceOver navigation. UI tests must cover rotation while review, window resize during scan, category switching with unapproved drafts, and tray consistency.

## Test grid

Use at least one iPad mini-sized window and one large iPad Pro-sized window, in portrait and landscape, and test a narrow resized window plus AX5. Assert no overlapping action controls, no invisible approval/abort affordances, preserved keeper state, no extra library client instances, and bounded decoded image memory. A passing iPhone simulator or isolated iPad compile does not satisfy this device gate. Real iPad confirmation/deletion and VoiceOver need their own device evidence.
