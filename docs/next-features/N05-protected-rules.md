# N05 — Never Suggest / protected rules

Status: specified; implementation follows first-scan integration closure. Source: owner-supplied premium-parity report, 2026-11-12. Do not infer that unavailable linked bundle specifications were read.

## Outcome

Users can exclude a photo or a date range from deletion recommendations and see why it is kept. With full Photos access, album rules may additionally protect current album members. Limited access supports asset/date rules and explains why album rules are unavailable. No face identity, cloud service or automatic deletion.

## Invariants

- Immutable SafetyPolicy, exact equality checks, preservation flags and the single PhotoKit deletion call stay authoritative. User rules can only exclude more deletions.
- A rule added after review/approval must invalidate affected tray decisions and block commit against fresh snapshots/current rules. Removing a rule never restores approval or auto-marks a photo.
- Rules protect a photo even when it appears in another category, reversed swipe orientation or a previously held review model. A protected keeper may remain visible as context.
- Persist rule intent (identifier/date/album rule), never image bytes or acknowledged safety authority. Local file protection, backup exclusion, versioned decode, atomic writes and corruption failure behavior require tests.
- No output analytics containing photo IDs, dates, names or raw rules. Reset requires a visible user action; deleting the rebuildable scan cache must not remove protections silently.

## Implementation increments

1. Core pure rule evaluator with explicit date boundaries, duplicate-rule normalization and tests. No deletion-policy modifications.
2. App-owned persistence and migration/corruption tests. One injected protection-checking interface shared by review, standalone, tray revalidation and commit coordinator; avoid an independent store per view.
3. Per-photo/date controls, rule management and visible kept-safe reasons, with phone and adaptive iPad layouts. Changes propagate to active drafts/tray.
4. Full-access album rules using public targeted album APIs. Resolve membership afresh before mutation; limited/restricted/unavailable rule resolution fails closed for potentially protected targets.
5. Adversarial integration/UI validation; append safety assertions. Commit/push coherent validated increments; owner physical-library evidence remains a separate release gate.

## Acceptance

Protect via regular review and swipe orientation; try approving from an already-open draft; protect after adding to tray; change/remove rules between validation and commit; revoke album access; edit asset capture time; relaunch with rules and tray persisted; corrupt/unknown rule schema; reset cache; limited Photos access; rotation/AX5; cancel all presentations. In every applicable case, protected targets never enter the single delete request, keepers survive, and removal of a rule creates no new authority.

Review final diff against this document, Core policy separation and original safety assertions. Run focused Core/persistence/integration tests and phone/iPad UI, then regression/budget checks. Record independent-review availability honestly: this session is the sole coding owner, so self-review is not an independent gatekeeper approval.
