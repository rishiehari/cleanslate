# S01: Swipe n Save

Owner-requested on 2026-11-11; takes priority over the earlier L28 deferral. The owner authorized building this feature while the F03 device stability gate remains PENDING. This does not waive that gate or authorize F04, distribution, or a real-library run.

## Experience

A second tab, **Swipe n Save**, invites a short daily review of existing pairs of similar photos. Swipe left keeps the left photo; swipe right keeps the right photo. Equivalent labeled buttons are always available. The center **Keep both** action leaves both photos alone and advances. A directional choice marks the other photo Delete; a separate **Approve** action adds it to the existing tray. Nothing is deleted by choosing or approving.

V1 uses original two-photo, non-video similar groups with direct similarity evidence. It does not split larger bursts, infer new similarities, scan extra photos, or introduce a streak or storage-savings claim. Reviewed groups, overlapping photos, and photos involved in pending tray entries are excluded. Empty states explain how to find results through Home.

## Safety and implementation constraints

- Preserve group IDs, pair evidence, and frozen snapshots. Choosing the original candidate as keeper must construct an orientation-specific review group so existing protection and face/text warning checks apply to the photo now marked Delete.
- Both orientations use `GroupReviewModel` and its analysis/acknowledgment gates. No automatic similar-photo preselection; no change to `SafetyPolicy`, preservation flags, deletion coordinator, or the single PhotoKit deletion call site.
- Re-resolve current results before approval. Changed members, revisions, flags, unavailable permissions, rechecking, or deletion in progress must block or invalidate a pending choice.
- Approval uses the existing tray, manual-review IDs, commit-time revalidation, summary, Apple confirmation, and receipt. Keep both uses the existing skip/undo behavior.
- Preserve the draft when switching tabs. Provide Undo, Compare, protection explanations, and tray access. Follow existing design tokens and ContentStateView; support large text, VoiceOver, button alternatives, and Reduce Motion.
- Use synthetic/fake libraries only. No network code or dependencies. Existing safety tests remain unchanged.

## Acceptance and evidence

1. Both directions keep the chosen photo and explicitly mark only its partner; Keep both adds nothing.
2. Choices and approvals make zero library deletion calls. Only the existing confirmed tray flow deletes through the coordinator.
3. Protection and warning/unavailable-analysis checks apply in either orientation, including when deleting the original suggested keeper.
4. Stale/removed pairs, overlapping groups, pending tray photos, repeated gestures, permission changes, Undo, and tab switching fail safely.
5. Core, lint, build, focused iOS/UI tests, regression CI, tier budgets, accessibility audit, and light/dark/AX3 screenshots are recorded honestly. Missing evidence remains UNVERIFIED.
6. Independent validator and final gatekeeper review precede a completion claim. Device gates remain PENDING.

See `PROGRESS.md` and `VALIDATION_LOG.md` for the current implementation and measured results.
