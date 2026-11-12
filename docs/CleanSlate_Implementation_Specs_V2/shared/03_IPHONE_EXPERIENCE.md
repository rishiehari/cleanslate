# iPhone-specific experience contract (not an enlarged iPad)

**Scope:** portrait-first, one-hand review, shallow navigation, compact screens and explicit destructive safety. Every feature file supplements this base with unique views and transitions. The app minimum currently declared in `project.yml` is iOS 26. Respect actual safe areas and Dynamic Type instead of freezing screen-pixel assumptions.

## Main navigation

Use existing dashboard and category routing; don't add ten permanent tabs. Recommended destination groups: Home, Swipe & Save, Discover, Review Tray, Settings. New features appear contextually as Home recommendations and Discover categories. The `AppDestination` navigation model (if/when added) must have stable identifiers to survive foregrounding and tab switching. Do not move an approved photo back into an unapproved selection merely because the user navigates backward.

## Standard first-value card

Every new feature that is empty until scanning completes must display one of three honest states: a seeded interactive *demo* (explicitly labeled "Example photos"), an already indexed real result (with scope and date), or a quick start action to analyze a bounded user-selected scope. It must never ask full-library permission just for browsing a static demo. A demo decision never calls PhotoKit mutation and never appears in real history/impact. Put the first actionable decision within two taps after an eligible result exists; instrument the actual value only on device.

## Review surface requirements

Portrait: use one card/photo or pair at a time, horizontally safe gestures away from the system back edge, large bottom controls in the thumb region, and pinned top metadata limited to 2 lines. Narrow phones: buttons wrap/stack without clipping; `minimumScaleFactor` is not a substitute for readable Dynamic Type. Large-text accessibility uses an explicit vertical review layout with controls following content rather than overlaying photos. Landscape: prefer useful full-image visibility with a right-hand action rail, keeping navigation and tray count accessible. Never hide safety reasons behind tooltip-only UI.

Standard actions: **Keep**, **Keep both**, **Review**, **Skip**, **Protect**, **Add to tray** (only after explicit approval), **Undo** (undo staged action, not Apple's completed delete). Labels should say "Ready in your tray" rather than "Freed space" after approval. Every potentially destructive action displays the surviving/photo context. Use `.confirmationDialog` or equivalent system confirmation for uncertain selections, but do not replace Apple's Photos deletion prompt.

## Gestures and haptics

Gestures are optional accelerators with equivalent named buttons. Swipe n Save's agreed semantics must be preserved: left retains left; right retains right; up keeps both. Don't capture scroll gestures inside multi-photo grids. A swipe decision does not itself approve removal. On iOS with VoiceOver enabled, expose custom actions without requiring directional dragging. Haptics are subtle, respect Reduce Motion, and never convey the only representation of success/failure.

## States and copy rules

- `noPermission`: "See a sample first. Photos access is optional until you scan." CTA: "Choose photos to check".
- `limited`: "Checking only the photos you've shared with CleanSlate." CTA: "Manage selected photos".
- `running`: "Checked 74 of 100 accessible items" plus current stage, reason for any pause, and **Pause**.
- `partial`: "Some originals were only in iCloud. Those files weren't verified." CTA: "Review available results".
- `empty`: "No eligible items found in this scope" plus next valuable action, not "Your library is clean".
- `stale`: "Some photos changed. Let's refresh these suggestions." CTA: "Recheck".
- `offline`: only mention network if user explicitly opted into original downloads; most features run offline.
- `error`: a clear retry path, no deletion or corrupted empty state.

## Accessibility, localization and usability

Visible controls ≥44×44pt; semantic headings; accessible image descriptions describe **why** items are shown, not subjective facial or emotional judgments. Announce changes to review state, with no repeated VoiceOver chatter for every scan counter tick. Support VoiceOver, Switch Control, Full Keyboard Access, bold text, Increase Contrast, Reduce Motion, RTL and English text expansion to at least 150%. All retention and protection actions must be discoverable without swiping.

## Screens shared across feature work

Home shows at most three relevant next actions. Discover lists categories; a FeatureView provides scan/coverage, result queue, detailed review, and an exit that preserves draft state. Tray remains the single destination for approved deletion; History stores confirmed operation receipts, not raw image content. Settings contains privacy, permissions, local data reset, download consent and relevant feature toggles. Do not duplicate tray/receipt logic in new views.
