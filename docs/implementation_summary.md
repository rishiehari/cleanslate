# Large-library implementation — current status

Updated 2026-11-12. Supersedes earlier unverified completion claims.

- Home shows a metadata-only overview of up to 5,000 recent accessible items, ranked by burst activity and weekly volume. No inferred trips, face analysis, original downloads, image bytes or photo IDs are stored in that summary.
- Suggested weeks start a date-bounded scan capped at 2,000 items. The default manual scan is the past month, capped at 2,000; past two months, latest 100, latest 1,000 and latest 2,000 are available. Album scanning is not implemented or offered. Repeating Latest 1,000 rechecks the latest items; it does not advance a cursor.
- Production scan inventory uses a dedicated serial queue, public PhotoKit date predicates/fetchLimit, 25-item pages and cancellation/deadline handling. A timed-out synchronous PhotoKit call may continue on that queue, but the UI returns and no additional asset work starts for the cancelled page. This is not evidence of real-device hang resolution.
- Every bounded scan rebuilds its active index membership so old full-library rows cannot escape the selected cap. Receipts and persisted tray schemas remain unchanged. Paused bounded inventories restart; cached fingerprints/digests may be reused only at matching revisions.
- Shared phone/tablet UI offers the same scan choices, review/tray path, progress banner and metadata overview. Wide windows additionally use the adaptive review/Compare layouts.
- Unavailable previews are not classified as iCloud-only. No unverified space savings or fixed timing estimates are advertised.

Validation evidence is in VALIDATION_LOG.md. Device gates remain pending; original safety policy, preservation flags and single deletion call site are unchanged.
