# N07 — Screenshot Intelligence: repeat detection, changed-text protection, and review packs

**Feature class:** advanced on-device grouping atop existing screenshots category. **Effort:** L, roughly 14–23 engineer-days plus privacy review. **Premium analogues:** Cleanup/CleanMyPhone/Flic market screenshot cleanup and intelligent sorting; the exact OCR safety method here is CleanSlate's design, not a proven vendor implementation. **Dependencies:** F04 scoped indexing/F05 progress, N05 protection, N04 goal planning as optional consumer.

## 1. Outcome and human-centered requirements

The basic screenshots list already exists in CleanSlate. N07's incremental promise is **help me find screenshots that are visually repeated without accidentally discarding changed information**. Typical cases: duplicate login instructions, receipts, event details, chat screenshots, maps/directions, ticket QR codes and a screenshot of an updated delivery ETA. A visually similar screenshot containing a different gate, seat, time, price, OTP, tracking number or message must remain **distinct** even if global image embedding similarity is very high.

A demo group of four synthetic ticket screenshots illustrates the benefit before Photos permission: images 1 and 2 are byte/near-render duplicates; image 3 has a new boarding gate; image 4 has different QR data. Present 1–2 as one review group; label 3–4 "Important changes detected — kept separate". User can try Compare and Keep both; no simulated action touches Photos. A truthful empty state says "No repeated screenshots found in the items checked" and offers age/month or large-file sorting, not "All your screenshots are junk."

N07 must not be a general semantic understanding chatbot and must not label a screenshot "unimportant" based on content alone. Do not extract contact data, OTPs, medical records or transaction amounts for any cloud model. No OCR text search or external classification in V1. All decisions are review-only, and standalone screenshot deletion uses the existing manual approval tray.

## 2. Classification pipeline and exact stages

**Stage A, inventory:** select only assets with PhotoKit `PHAssetMediaSubtype.photoScreenshot` under the current authorization scope. Optionally include screen recordings in a separate category; never decode video frames in screenshot worker. Paginate descending by date using `LibraryStore`, with scope revisions. Do not identify screenshots solely from filenames.

**Stage B, cheap candidate hashing:** request a local downscaled raster (target e.g. 256px max axis with documented quality), compute perceptual/difference hash and aspect/resolution bucket. Nearby time and same pixel dimensions are *candidate hints*, not proof. Use hash band indices to find a bounded candidate set; no O(N²) all screenshots comparison.

**Stage C, OCR guard:** for each candidate pair (not the entire library indiscriminately), perform Vision text recognition offline. Extract bounding rectangles, language probability where exposed, normalized text lines and high-entropy token categories **in ephemeral memory**. Normalization may fold whitespace and punctuation but must NOT fold digits, currency, addresses, URLs, codes, dates, times or alphanumeric tokens. A conservative changed-text guard rejects equivalence if salient text differs. Distinguish OCR unknown from OCR equal; unknown requires manual review without a redundancy badge. Use Vision `VNRecognizeTextRequest` or supported Swift `RecognizeTextRequest` after SDK validation; do not assume a simulated Vision request works on every runtime.

**Stage D, structural comparison:** align images using aspect ratio and small transforms; compare hashes/feature prints plus text rectangle overlap. If text is confidently identical *and* image geometry is close, form a **possible repeated screenshot** group. If text differs or OCR confidence is poor, show a paired comparison labeled "Review differences" or keep separate. QR/barcodes contain meaningful changes that OCR may miss: V1 detects high-contrast block differences and always abstains from duplicate qualification when such regions differ; do not pretend to decode all QR content. Future Vision barcode detection requires separate tests/permissions/accuracy gate.

**Stage E, user experience:** generate pairwise evidence of screenshot relation, not a blanket group edge. A group of 3 uses a keeper set only if every proposed removal has direct evidence to a surviving keeper. Similar screenshot groups are NEVER preselected. Exact byte-equal resources may use existing exact flow, with normal protection checks.

Illustrative rule (not statistically calibrated): `candidate = dHashBucketsOverlap && aspectWithinTolerance`, `reviewSimilar = visualDistanceWithinConfiguredBound && !salientTextDifference && !barcodeDifference`, `confirmedExact = ResourceSignatures.canonical(allResources) equality`. Thresholds live in versioned configuration and must be calibrated on hard negatives. Log counts of unknown OCR separately; no hard-coded '90% safe' claim.

## 3. Data model and persistence

```sql
CREATE TABLE screenshot_features(
 asset_id TEXT NOT NULL, revision TEXT NOT NULL, algorithm_version INTEGER NOT NULL,
 screenshot_kind TEXT NOT NULL CHECK(screenshot_kind IN ('image','recording')),
 phash_bands BLOB,
 text_hmac BLOB,             -- keyed digest ONLY; not raw OCR
 text_block_count INTEGER,
 high_entropy_token_count INTEGER,
 text_confidence_bucket INTEGER,
 text_change_guard INTEGER NOT NULL DEFAULT 0,
 barcode_sensitive INTEGER NOT NULL DEFAULT 0,
 status TEXT NOT NULL CHECK(status IN ('ready','unavailable','failed','stale')),
 updated_at REAL NOT NULL,
 PRIMARY KEY(asset_id,revision,algorithm_version)
);
CREATE INDEX screenshot_status ON screenshot_features(status,updated_at);
CREATE TABLE screenshot_review_edges(
 id TEXT PRIMARY KEY, left_asset_id TEXT NOT NULL, right_asset_id TEXT NOT NULL,
 left_revision TEXT NOT NULL, right_revision TEXT NOT NULL,
 evidence_kind TEXT NOT NULL, algorithm_version INTEGER NOT NULL,
 review_only INTEGER NOT NULL DEFAULT 1, created_at REAL NOT NULL
);
CREATE INDEX screenshot_edge_left ON screenshot_review_edges(left_asset_id);
```

Use a **per-install Keychain secret** to HMAC canonical text fingerprints. If secret changes or unavailable, invalidate/regenerate the fingerprints; do not write plaintext OCR as fallback. HMAC equality indicates normalized line text equality, not screenshot resource equivalence; line order/bounding box also matters. Protection flags must be considered at every display/approval. Logs store only counts and coarse durations, never text length as a unique fingerprint in diagnostics. By default store no recognized strings, bounding-box text pairs, or image crops on disk. Group edges cache invalidates on either revision or OCR version change.

## 4. Proposed Swift interfaces

```swift
struct ScreenshotCandidateKey: Sendable {
  let assetID: String
  let revision: String
  let aspectBucket: Int
  let hashBands: [UInt16]
}
struct SalientTextEvidence: Sendable {
  let normalizedTextHMAC: Data? // nil on unknown
  let blockCount: Int
  let criticalDifference: Bool
  let confidenceClass: OCRConfidenceClass
  let barcodeStructureChanged: Bool
}
enum ScreenshotRelation: Sendable {
  case byteIdentical
  case visualAndTextMatchForReview
  case changedInformation
  case inconclusive
}
protocol ScreenshotAnalyzing: Sendable {
  func candidateKey(_ image: CGImage, revision: String) async throws -> ScreenshotCandidateKey
  func textEvidence(_ image: CGImage) async throws -> SalientTextEvidence
  func compare(_ left: ScreenshotAnalysis, _ right: ScreenshotAnalysis) -> ScreenshotRelation
}
actor ScreenshotIndexCoordinator {
  func analyze(scope: ScopeDescriptor, cursor: String?) async throws -> ScreenshotProgress
  func reviewGroups(after cursor: String?, limit: Int) async -> [ScreenshotReviewGroup]
}
```

Use `@MainActor PhotoLibraryClient` only to acquire authorized thumbnails; expensive raster processing occurs off main with bounded concurrency and autorelease pools. `ScreenshotIndexCoordinator` persists ephemeral evidence into `LibraryStore` via an extension, not a separate writer. OCR may fail because of scripts/language/low contrast; failure is `inconclusive`, never text equality. Expose `recognitionLanguages` and revision as settings only if testing supports them; keep bilingual canaries.

**State machine:** `notIndexed → candidatesFound → comparing → reviewReady/changedInformation/unknown → reviewed/keptBoth/trayApproved` and independent `paused/stale/failed` substates. A new Photos screenshot inserted while scanning is discovered via next incremental inventory, not by restarting all OCR. If scanner stops at 500, coverage explicitly says 500 checked.

## 5. iPhone UX design

**Screen 1, category overview:** Screenshot Intelligence card appears below existing screenshot category, showing "27 repeated-looking screenshots to review" plus "6 with changed text kept separate" **only if measured in current scope**. If no OCR has run, display "Analyze repeated screenshots" with scan scope and expected local-only processing disclaimer. No pushy storage goal.

**Screen 2, review packs:** segmented controls "Repeated", "Changed info", "All"; each pack shows overlapped thumbnails and badges "Possible repetition"/"Important text may differ". The latter is a warning, not a claim the text is unimportant. Tap a pack for compare. A monthly filter is optional; all counts use permitted scope.

**Screen 3, difference compare:** two full-width screenshots stacked on narrow phones, pinch zoom with a dedicated Diff toggle. When diff is active, overlay bounding rectangles for changed regions computed transiently; do not persist text snapshots. If OCR uncertain, say "We couldn't compare every word. Check both images." Buttons: Keep left, Keep both, Keep right, Protect, Skip. Destructive choice is not approved until the separate Approve action, then tray. Never show a single "Delete all old screenshots" shortcut.

**Screen 4, result:** "Reviewed 8 screenshot pairs · 3 items ready in tray · 4 different information sets preserved". If user kept both, count as a successful review. View tray is optional; Done for now prominent.

## 6. iPad UX design

Sidebar has screenshot categories (Repeat candidates, Changed info, By month, Unchecked); main pane uses dense pack gallery with enough context to identify screen contents; detail pane compares side-by-side with synchronized zoom and a transient diff overlay. Pointer can hover to reveal Compare but cannot stage deletion; keyboard arrow keys switch pack, `K` optional for Keep both *only when focused review*, Escape returns to pack. Narrow Stage Manager windows collapse to phone-style compare; OCR work does not double when two panes request a pack. VoiceOver provides "Possible similar screenshot. Some text differs" plus a count of changed regions, never reads sensitive OCR text by default. A user may explicitly use system text recognition on their visible screenshot through the accessibility system; CleanSlate does not store those recognized strings.

## 7. Security, performance and failure cases

- OCR containing passwords, financial IDs, codes, health data, private chats: discard plaintext after processing and apply OS data protection to derived cache.
- Recompressed screenshot loses exact bytes but not visible content: still manual review; no exact label.
- Text differs by one digit (flight gate, price, OTP): preserve as changed information even when a hashing heuristic considers them close.
- Same text, changed QR code, photo or chart: preserve; OCR equality isn't enough.
- Different languages or no OCR coverage: inconclusive, show side-by-side, no automatic pair elimination.
- Screenshot in Live Photo or edited asset oddity: existing conditional protection applies.
- Permission revoked between OCR and review: invalidate and hide thumbs; do not show cached raw screenshots.
- Photo appears in protected album: respect existing hard album protection and N05.
- Performance: bounded local thumbnails, one OCR worker on low tier, model cache evicted on memory warning, governor checkpoint after each candidate group, cancellation every asset. Large-screenshot count may be >50k, but pair generation must use hash buckets and limited probes, not all pairs.

## 8. Gherkin, test plan and physical-device gate

```gherkin
Scenario: Single-digit difference blocks a repeated-screenshot claim
 Given two image-identical boarding passes differ only by gate "B12" versus "B13"
 When Screenshot Intelligence compares them
 Then evidence is changedInformation or inconclusive, not equivalent
 And neither photo is preselected to remove

Scenario: OCR cannot read a low-contrast screenshot
 Given a valid screenshot with unreadable text
 When OCR fails or confidence is below the validated gate
 Then the result remains reviewOnly with an uncertainty explanation

Scenario: User keeps both sides of a repeated pair
 Given a displayed screenshot pair
 When the user selects Keep both
 Then no item is added to the tray
 And the local session counts one completed review

Scenario: Permission revoked between analysis and approval
 Given a cached screenshot review pack
 When Photos authorization is revoked
 Then approval is blocked, previews are cleared and scope is marked stale
```

**Fixtures:** exact PNG pair, compressed JPEG version, one-digit change, different QR pixel blocks, multiline receipt with changed total, night-mode color inversion, right-to-left mixed-language screenshot, very small text, screenshot containing a person photo, scrolling long screenshot. Test different color spaces and cropped overlaps. Human-label 100+ realistic screenshot families only with proper consent; record precision/review burden without exporting private OCR. Unittest comparator and HMAC secret reset; integration SQLite keys + migration; iOS Vision OCR on device; UI demo/changed-text warning/AX5, iPad diff pan/resize; memory soak 10k fake assets.

Proposed go/no-go: **zero unsupported automatic screenshot deletions** (by construction), no plaintext OCR persisted, changed-digit and changed-barcode canaries always fail closed, generator and scan progress/cancel reproducible, core synthetic and user-rated hard negatives evaluated. No release claim of OCR accuracy without representative real data.

## 9. Implementation commits, switches and fallback

1. N07.1 pure typed evidence and negative test corpus.
2. N07.2 screenshot feature table, Keychain HMAC service, migration and purge test.
3. N07.3 bounded Vision OCR adapter and changed-token guard with cancellation.
4. N07.4 retrieval/grouping/revision invalidation and real coverage accounting.
5. N07.5 iPhone packs/diff and existing tray integration.
6. N07.6 iPad multi-pane compare, keyboard/pointer/VoiceOver.
7. N07.7 field validation and privacy/security review.

Suggested files: `Core/Sources/CleanSlateCore/ScreenshotEvidence.swift`, `App/Services/ScreenshotAnalyzer.swift`, `App/Services/ScreenshotFeatureStore.swift` (prefer `LibraryStore` extension), `App/Views/ScreenshotIntelligenceView.swift`, `App/Views/iPad/ScreenshotWorkspace.swift`, `iOSTests/ScreenshotEvidenceTests.swift`, `UITests/ScreenshotReviewUITests.swift`. `N07Enabled` OFF until gates; rollback disables classifier and preserves manual screenshot list. Never remove source Photos assets or encrypted cache keys as part of feature rollback; local reset is explicit.

**Sources:** https://developer.apple.com/documentation/vision/recognizing-text-in-images ; https://apps.apple.com/us/app/cleanup-phone-storage-cleaner/id1510944943 ; https://apps.apple.com/us/app/cleanmy-phone-cleanup-storage/id1277110040 ; https://github.com/rishiehari/cleanslate/blob/main/App/Models/PhotoModels.swift
