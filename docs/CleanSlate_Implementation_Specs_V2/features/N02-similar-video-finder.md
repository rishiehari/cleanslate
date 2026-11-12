# N02 — Similar and Re-encoded Video Finder

**Priority:** after stability, quality/moment validation. **Effort:** XL, ~20–35 engineer-days plus device/codec matrix. **Paid analogues:** Cleanup and Cleansmith promote similar/lookalike video detection; product listings are feature advertisements, not audited matching accuracy. **Constraint:** Apple PhotoKit originals may be remote in iCloud; the default scanner must not download or decode them silently.

## 1. Jobs to be done and first 30-second experience

Users often save the same clip through chat apps, social downloads or exports at different resolutions, trim a few seconds, or record duplicate takes. Videos can dominate storage, so finding one true redundant pair may beat hundreds of screenshots. But a clip of the *same event with a different moment or soundtrack* is not an interchangeable duplicate.

First-run permission-free demo: show three locally bundled 4–8 second synthetic videos, each represented by timeline thumbnails. A and B depict the same moving object but B is re-encoded at lower resolution; C shares the initial frame but changes the ending. App labels A/B "Possible re-encode — review" and C "Different ending — kept separate". No network or media export. With actual permission, a lightweight local index surfaces large video *candidates* first, then user chooses "Compare selected videos" to trigger bounded frame extraction. Display progress by videos examined, not made-up percent of entire library.

**Non-goals:** detect copyright duplicates across the internet, transcribe all audio, search by person identity, delete similar videos automatically, infer scene identity with a huge online model, guarantee all re-encodes can be found, analyze every video frame, or download cloud originals without consent.

## 2. Candidate retrieval and precise video comparison pipeline

**Level 0 — metadata inventory:** use PhotoKit video type, creation time, duration, dimensions (where accessible), file resource summary and local availability. Do not trust duration alone for equivalence; trimmed clips need their own tentative relation. Keyset-page video rows from SQLite by duration bucket/aspect ratio and hash-local candidate metadata. Album/favorite/edit/slow-mo/cinematic/spatial/Live specifics may carry extra preservation semantics and must be protected by existing policy.

**Level 1 — inexpensive plausible-pair retrieval:** candidate pairs if duration ratio within a versioned tolerance, rough dimensions/aspect match and temporal neighborhood OR filenames/resources suggest a shared export. To catch re-encodes saved months apart, use 1–2 downscaled poster frames *only for opted-in candidate scans* and bucket their perceptual hashes. Avoid O(V²) comparisons: a bounded inverted index and capped top-K per asset. Source filename is weak evidence; never construct equivalence solely from it.

**Level 2 — local frame sampling:** acquire a locally available AVAsset or authorized export handle using `PHImageManager.requestAVAsset(forVideo:options:)`/supported PhotoKit APIs and allow network **false** unless opt-in. Validate type, duration and accessibility. With `AVAssetImageGenerator`, sample normalized timestamps `t ∈ {0.05,0.15,0.3,0.5,0.7,0.85,0.95}` (illustrative; versioned and evaluated) plus first/last when needed; samples must avoid solely duplicate I-frames. For trimmed clips, test candidate temporal offsets rather than assuming 0% aligns with 0%; cap alignments and mark inconclusive if expensive. Decode one asset at a time on low-memory device. Frame rasters ≤320px for initial analysis, disposed immediately.

**Level 3 — temporal alignment evidence:** compare sequences using bounded dynamic time warping or ordered approximate alignments; require evidence across beginning, middle, end, not just first frame. Compute visual hash/feature print agreement plus differences in duration, dimensions, orientation, color space and audio track presence. Audio does not require speech recognition: use track existence/duration/channels only for conservative guard; different audio should block equivalence claims. Soundtrack or commentary differs → review, not 'same video'. Captions/text may change → mark uncertain; N07 screenshot OCR logic may be reused only for selected frames if licensed/appropriate.

**Level 4 — classification:** `byteIdentical` only after verified complete resource signatures. `reEncodedCandidate` when visual evidence is strong but full resources differ, always manual. `trimmedSubset` indicates plausible shared segment but not redundancy; by default show separate. `distinct` for obvious divergent ending/subjects, `inconclusive` if media inaccessible or sampling failed. Never map `reEncodedCandidate` to the Core's `exactResources` relation. No auto-preselected similar videos.

## 3. Domain types, persistence and API adapter

```swift
enum VideoRelation: Sendable {
 case verifiedExactResources
 case likelyReencodedForReview
 case partialOverlapForReview
 case distinct
 case inconclusive(reason: String)
}
struct VideoFrameSignature: Codable, Sendable {
 let normalizedTimePermille: Int
 let perceptualHash: UInt64?
 let featureVersion: Int
}
struct VideoAnalysis: Sendable {
 let assetID: String; let revision: String
 let durationMS: Int64
 let frameSignatures: [VideoFrameSignature]
 let audioTrackCount: Int?
 let colorSpaceClass: String?
 let availability: LocalMediaAvailability
}
protocol VideoFrameSampling: Sendable {
 func sample(assetID: String, revision: String,
             timestamps: [Double], allowNetwork: Bool) async throws -> VideoAnalysis
}
protocol VideoPairComparing: Sendable {
 func compare(_ a: VideoAnalysis, _ b: VideoAnalysis,
              workBudget: PairWorkBudget) throws -> VideoRelation
}
```

`VideoFrameSampling` must be an app-side PhotoKit adapter whose authorization-sensitive fetch runs with the existing `@MainActor` library service. Perform frame processing off-main using a bounded serial queue/task actor; document cancellation, export cleanup, AVAsset release and progress callback behavior. A fetch is **local-only** by default. Use typed errors `unavailableCloudOriginal`, `unsupportedCodec`, `permissionRevoked`, `timedOut`, `cancelled`, `thermalPaused`, `corruptMedia`.

```sql
CREATE TABLE video_signatures(
 asset_id TEXT NOT NULL, revision TEXT NOT NULL,
 version INTEGER NOT NULL, duration_ms INTEGER NOT NULL,
 frame_summary BLOB, audio_track_count INTEGER,
 availability TEXT NOT NULL, analyzed_at REAL NOT NULL,
 PRIMARY KEY(asset_id,revision,version)
);
CREATE TABLE video_review_edges(
 left_id TEXT NOT NULL, right_id TEXT NOT NULL,
 left_revision TEXT NOT NULL, right_revision TEXT NOT NULL,
 relation TEXT NOT NULL, evidence_version INTEGER NOT NULL,
 requires_manual_review INTEGER NOT NULL DEFAULT 1,
 PRIMARY KEY(left_id,right_id,evidence_version)
);
CREATE INDEX video_edges_by_right ON video_review_edges(right_id);
```

Persist compact frame signatures, not actual video frames, decoded audio, transcripts or filenames. Invalidate both edges on revision changes; a new edit/trim rechecks all prior evidence. Verify app storage budget and `isExcludedFromBackup` for temporary files. A failed read inserts `availability=unavailable`, not fabricated identical frame hashes.

## 4. State machine, grouping and review safety

`notScanned → metadataCandidates → sampling → compared → groupReady/partial/unknown → userReviewed → trayApproved`. Batch can transition to `pausedByThermal`, `pausedByLowMemory`, `awaitingUserDownloadOptIn` or `cancelled`. A user can leave the app with a partial result and resume from checkpoint; never restart full decoding from photo zero without reason. Groups are anchored to a parent pair evidence record; a four-video transitive chain does not permit deletion by group membership. Existing core safety must revalidate complete resources for verified exact videos at commit. A re-encoded pair can only reach tray through **explicit preview and review** and must preserve an adequate surviving keeper, including audio/trim differences the app may not be able to determine. If the user explicitly chooses to delete a unique standalone video, use the existing standalone manual path and label it as such; no false redundant-content guarantee.

## 5. iPhone design, screens, interactions

**Category card:** "Video matches worth comparing" with count and known bytes only for resource-verified items. Secondary description: "We'll compare short local previews; nothing uploads". Button "Check local videos" opens scope and optional maximum scan work. Avoid vague "clean every video" CTA.

**Video review list:** each candidate row has stacked movie posters, duration/source resolution, status chip "Identical file" or "Possible re-encode", and whether original is only in iCloud. Selecting row opens a split timeline comparer. Unavailable original row says "Video can't be checked locally" and offers opt-in original check with file-size/connection disclosures if existing policy supports it.

**Compare screen:** two synchronized video players with a playhead/filmstrip; initially muted to avoid two audio tracks; separate controls to listen to A/B, toggle sync, compare at 25/50/75%. Users can Keep A / Keep both / Keep B, Protect / Skip. On small phone screens players stack; portrait landscape can rotate for larger side-by-side viewing. Don't automatically stage a choice when one video finishes playback. Confirmation shows filename only if visible from legitimate PhotoKit metadata, and all missing audio/trim issues are explicit warnings.

**End-state:** "3 pairs reviewed · 1 approved for tray · 2 kept" plus bytes clearly distinguished by verified resource state. A pair marked distinct remains available for no-deletion outcomes.

## 6. iPad native UX and input

In wide window, video-pair queue left, dual timeline/video compare center, evidence inspector and persistent keeper selection right. A single video plays at a time unless user manually requests sync; pausing/reorienting preserves both playheads. Pointer scrubbing supports precise comparison; keyboard Space play/pause the focused video, arrow +/- short seek, K Keep both only in review focus, Escape leave. Do not bind Delete to PhotoKit mutation. Narrow Stage Manager window stacks players and collapses inspector; scrubber must remain reachable with VoiceOver and Full Keyboard Access. Frame decode is not duplicated between two panels; use one shared prefetch cache. Show duration/track availability as text, not solely visual timeline colors.

## 7. Adversarial cases and device budgets

Must test 4K/60 HDR HEVC, 1080p H.264, VFR, portrait, front-camera mirrored, trimmed beginning/end, slow-motion, cinematic, spatial video, live-photo paired resources, stereo/mono audio difference, mute/re-encode, intro card inserted, caption/burned text, same keyframe but changed end, corrupt file, iCloud-only asset, limited Photos permissions, transient Photos edit during hashing, 30-minute recording and 500 MB near full disk.

Use synthetic clips with deterministic moving shapes/scene cuts and artificial audio tracks for automated tests, plus consented device-made video corpus for real evaluation. Benchmark decode count per candidate, peak memory, thermal state and battery on lowest supported phone and an iPad; cap sampled frames and preview cache by device tier. Proposed proof gate: zero auto-staged non-exact video removals, zero cross-mode unsafe exact classification, all changed-ending/audio cases remain manual or distinct, no silent original downloads. Evaluate recall/precision for *review suggestions* only after human labeling; synthetic canaries are not a published accuracy estimate.

## 8. Acceptance scenarios

```gherkin
Scenario: Re-encode is not byte identity
 Given visually similar videos with different encodings and resource bytes
 When they are compared
 Then their relation is likelyReencodedForReview or inconclusive
 And neither is preselected for removal

Scenario: Same opening, different ending
 Given two clips with an identical opening but distinct final scene
 When normalized frame sampling runs
 Then the comparator does not label them verified exact or interchangeable
 And the review shows different-ending evidence

Scenario: Cloud-only video by default
 Given a Photos video whose original is only in iCloud
 And the user has not opted into network verification
 When the video scan reaches it
 Then there is no automatic download
 And it is counted as unavailable rather than a completed comparison

Scenario: Thermal pause survives app exit
 Given a long video analysis batch
 When the governor reports serious thermal state
 Then the job checkpoints and pauses with a reason
 And resuming does not duplicate approved reviews or Photos changes
```

Tests: `Core` temporal-alignment comparator; SQL migration/edge invalidation; fake AVAsset sampler and cancellation; simulator UI + synthetic videos; on-device hardware decode/HDR/audio; limited access and iCloud opt-in; 10k metadata-index perf; idempotent resume; iPad narrow/large/VoiceOver; existing deletion coordinator exact canary.

## 9. Engineering steps and release switch

1. Build pure metadata candidate index and temporal comparer (`Core/Sources/CleanSlateCore/VideoSimilarity.swift`), with explicit false-match negatives.
2. Add local media adapter (`App/Services/VideoFrameSampler.swift`) and resource governor support.
3. Append `video_signatures` / `video_review_edges` migration and batch checkpointing.
4. Integrate VideoReviewModel and real PhotoKit preview (`App/Models/VideoReviewModel.swift`).
5. iPhone video pairs and player (`App/Views/SimilarVideoReviewView.swift`); existing tray unchanged.
6. iPad video workspace (`App/Views/iPad/VideoComparisonWorkspace.swift`).
7. Test corpus and cross-device codec/thermal validation, update logs.

Flag `N02VideoSimilarityEnabled` OFF until device evidence. Rollback disables similarity analysis; existing exact-video and large-video categories remain unaffected. No unverified video may be marked identical or deleted without user choice. **Done** only when real-device AVFoundation media tests and safety gates pass.

**Sources:** https://apps.apple.com/us/app/cleanup-phone-storage-cleaner/id1510944943 ; https://apps.apple.com/us/app/cleansmith-photo-cleaner/id926090192 ; https://developer.apple.com/documentation/avfoundation/avassetimagegenerator ; https://developer.apple.com/documentation/avfoundation/creating-images-from-a-video-asset


## Privacy and consent boundary

Frames, waveforms, audio sample buffers and AVAsset temporary copies never leave the device. Cache only compact sampled signatures and duration/track-class metadata, protected and excluded from backup where appropriate. No speech transcription, person identity labeling, content recognition or upload is required. A video visible as an iCloud thumbnail is not permission to download its original; the existing network policy remains the sole opt-in path. Never save raw audio into diagnostic logs. On limited-Photos revocation, discard active preview buffers, invalidate unavailable evidence and restore safe read-only state; retain no stale image displays.
