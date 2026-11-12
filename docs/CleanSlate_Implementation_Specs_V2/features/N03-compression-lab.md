# N03 — Compression Lab: verified replacement, no silent loss of originals

**Priority:** after N02 video adapters and stability gates. **Effort:** XL, ~25–45 engineer-days plus codec/device testing. **Premium analogues:** CleanMyPhone and Cleansmith advertise video/photo compression and Live Photo conversion. **Risk:** highest operational data-integrity risk of all ten new features. **Absolute rule:** creation of a smaller file is *not* permission to delete the original.

## 1. User jobs, ethical first value and scope

Users with large videos want to know whether re-encoding one file would save meaningful storage without obvious quality loss. A good first session does not need the user's real media: a bundled public-domain/synthetic video with two local encoded variants demonstrates original size, actual output size and side-by-side difference. State that the sample is illustrative, and never imply identical results across personal videos. In the real library, choose a single eligible local video, show likely compatible output presets, run an optional **sandboxed trial export**, then show exact measured output bytes and a comparison before the user chooses **Save compressed copy**. Original remains untouched. After verifying the copy exists in Photos, offer a separate "Review original for deletion" flow through the existing tray; the user may keep both forever.

V1 supports a carefully chosen subset of locally available H.264/HEVC **video** without unsupported HDR/spatial/Cinematic/slow-motion metadata, and no Live Photo or RAW conversion. Display "Unsupported in this version; original untouched" for complex media. Add still-image compression/Live→still only as separately gated later increments after media invariants and sidecar handling are proven. Do not frame Live→still as lossless compression: it discards motion and is a **transform**. Never promise a specific compression ratio in advance.

**Non-goals:** altering photo quality in place; replacing an Apple Photos asset atomically; modifying iCloud Photos quota directly; silently changing HDR, color profiles, spatial data, depth, audio or time metadata; background compression without user initiation; third-party transcoding SDKs with unclear licenses; hidden upload to a cloud encoder.

## 2. User safety invariants

The irreversible-risk pathway is: **request source → export temporary derivative → validate derivative → request Photos creation → resolve new Photos asset → verify the new asset → optionally nominate old asset for review → existing tray/Photos confirmation for original deletion**. No phase skips. A crash after Photos asset creation must be reconciled from journal rather than blindly repeat creation. If verification fails, leave original untouched, mark job needs attention, and offer to remove the *new orphaned derivative* only with a separate explicit Photos review; do not clean up by deleting any possibly valuable asset automatically.

If source is a Live Photo, RAW+JPEG pair, Apple ProRAW, edited asset, HDR10/Dolby Vision/spatial video, Cinematic or slow-motion package and the pipeline cannot preserve all intended semantics, V1 must reject with an explanation. Unknown metadata is not assumed safe. A saved compressed copy must be identified as a new asset; album membership, creation date, location, captions, favorites and edits may **not** transfer automatically. Disclose any metadata not preserved and let the user opt out of saving rather than silently losing metadata.

## 3. Capability negotiation and export design

**Media admission: `canProcess`** inspects only public PhotoKit/AVFoundation metadata and existing protection rules. Check media type, local availability, duration, codec, dynamic range, audio tracks, pixel size, estimated temporary space, current battery/thermal state and Photos write authorization. A photo protected against deletion may still be compressed to a new copy as a nondestructive user action, but its original remains unremovable by CleanSlate unless the rule is explicitly lifted. Reject with typed reason on unsupported class.

**Preset planning:** provide e.g. *High quality* and *Smaller size*; both are target profiles, not promised file sizes. Validate supported `AVAssetExportSession` presets/file types for the actual asset at runtime. Preserve orientation and audio track selection or mark no support. Avoid forcing HEIC→JPEG where output may become larger. An output larger than original is a failed savings opportunity, not a user success; present "No useful reduction" with option Keep original/discard temporary copy.

**Trial export:** export source into a unique app container temp directory; use system AVFoundation API, ensure disk space before starting (source size + predicted output reserve, not a guarantee), stream progress and user cancellation, pin one export job at a time on low-tier devices, keep UI responsive. After export, validate file exists and length >0, independently open with AVFoundation and decode representative frames at start/middle/end, check actual duration within validated tolerance, orientation/aspect, audio channel presence, container, HDR profile/color primaries as applicable, playback from beginning/end and file integrity. A checksum of the original and output will differ; do **not** call them bit-identical.

**Perceptual QA:** allow explicit side-by-side preview (synchronized playback; quality toggle; actual/approx bitrate details). If metrics such as PSNR or SSIM are computed, they are *supplementary* and cannot guarantee subjective quality; implement with downsampled frames and bounded memory. Warn when color/HDR conversion or audio differences are detected. User chooses Save copy; use `PHPhotoLibrary.performChanges` to create a new asset from verified export and capture placeholder ID if available, then refetch and verify actual new asset. Persist a journal record before Photos mutation to recover from interruption.

## 4. Proposed types and typed state machine

```swift
enum CompressionStage: String, Codable, Sendable {
 case planned, exporting, exported, validating, readyForPreview,
      creatingPhotosAsset, reconciling, copyVerified,
      originalReviewOffered, finished, cancelled, failed, uncertain
}
struct CompressionProfile: Codable, Sendable {
 let name: String; let fileType: String; let presetName: String
 let maxDimensions: CGSize?; let preserveAudio: Bool
 let supportedMediaClasses: Set<MediaCapability>
}
struct CompressionJob: Codable, Sendable {
 let jobID: UUID; let sourceAssetID: String; let sourceRevision: String
 let originalVerifiedBytes: Int64?
 let profile: CompressionProfile
 var stage: CompressionStage
 var temporaryRelativeFile: String?
 var outputMeasuredBytes: Int64?
 var createdAssetID: String?
 var failureCode: String?
 var lastUpdate: Date
}
protocol MediaCompressing: Sendable {
 func capability(for asset: PhotoSnapshot) async -> CompressionCapability
 func exportTrial(jobID: UUID, profile: CompressionProfile) async throws -> TrialExport
 func validate(_ export: TrialExport, against source: PhotoSnapshot) async throws -> ValidationReport
 func saveVerifiedCopy(_ export: TrialExport) async throws -> CreatedPhotosAsset
}
```

State transitions: `planned → exporting → exported → validating → readyForPreview → creatingPhotosAsset → reconciling → copyVerified → finished`. Error/cancel can happen from any nonterminal state. A `creatingPhotosAsset` process crash resumes in `uncertain`, with **read-only reconciliation** (never auto-create a second copy and never delete source); a retry must use a user-visible idempotency resolution flow. `copyVerified → originalReviewOffered` only after a fresh source snapshot and protection evaluation, and the user must choose it. If Photos prompts cancel, leave both assets intact. A stale source edit invalidates trial comparison (source revision mismatch) and blocks offering original deletion.

## 5. SQL and file-journal contract

```sql
CREATE TABLE compression_jobs(
 job_id TEXT PRIMARY KEY, source_asset_id TEXT NOT NULL,
 source_revision TEXT NOT NULL, profile_json TEXT NOT NULL,
 stage TEXT NOT NULL, original_verified_bytes INTEGER,
 output_measured_bytes INTEGER, temporary_relative_path TEXT,
 created_asset_id TEXT, failure_code TEXT,
 created_at REAL NOT NULL, updated_at REAL NOT NULL
);
CREATE INDEX compression_jobs_status ON compression_jobs(stage, updated_at);
CREATE TABLE compression_validation(
 job_id TEXT PRIMARY KEY REFERENCES compression_jobs(job_id) ON DELETE CASCADE,
 video_duration_delta_ms INTEGER, frame_decode_count INTEGER,
 audio_track_status TEXT, dynamic_range_status TEXT,
 orientation_status TEXT, user_preview_accepted INTEGER NOT NULL DEFAULT 0,
 validated_at REAL
);
```

Never store absolute external file paths, source media bytes or thumbnail/image data in SQLite. `temporary_relative_path` resolves inside a dedicated, protected, backup-excluded app directory after canonical path validation. On app launch, scan journal for unfinished jobs; don't delete a temp file referenced by a nonterminal row. A background cleanup job can remove abandoned *temporary application files* after safe timeout and confirmed no Photos mutation; it cannot delete Photos assets. Enforce per-job disk budget and total cache budget. If the user presses Delete CleanSlate Local Data, explain that unsaved compression trials will be discarded; any new Photos assets already saved remain in Photos.

## 6. iPhone screens

**Compression eligibility list:** show verified local large videos, sortable by measured source bytes, resolution and duration. Badges for HDR/Unsupported/Cloud-only. A disabled item offers a reason, not an unconditional CTA. Starting a trial displays privacy statement "Compression happens on this iPhone. Your original will remain in Photos."

**Preset sheet:** two to three profiles at most, with quality/compatibility language and estimated bounds only when conservative evidence exists. Include source metadata details and temporary space requirement. No ad/paywall, no automatic 'recommended' compression without actual trial.

**Export progress:** one clear running job, measured bytes processed when available, time elapsed, cancel, pause if supported by export API, low-battery/thermal explanations. Apple background execution is not guaranteed; if interrupted, resume/retry from a saved state as system APIs allow. Avoid fake 100% progress.

**Side-by-side preview:** original vs compressed, synchronized playhead, audio A/B toggle, zoom, source/output actual byte size, original/new dimensions and any lost/unknown metadata. CTA "Save compressed copy" plus "Keep original and cancel". If output is larger, highlight "No storage benefit" and default to cancel.

**Saved receipt:** "Compressed copy saved in Photos; original still there." Show original 800 MB, new 340 MB, **difference 460 MB *if original is later removed***. The user's actual storage has temporarily increased; be explicit. Secondary CTA "Review the original for deletion" opens the existing review/tray with a comparison and protection checks; never delete in-place.

## 7. iPad layouts and native interaction

Wide iPad: left job/source list, middle dual synchronized video previews, right metadata/validation inspector. Keep a persistent job-status column; a transcode can continue while a user reviews other **existing results**, but no second heavy encoder starts without a governor check. Resizable window adapts to stacked preview with full metadata accessible. Keyboard Space controls focused player, arrows scrub, Escape cancels the current dialog only, Command-S may save output only through explicit confirmation after review; do not bind Delete to source removal. Pointer scrub/hover shows frame time, not hidden destructive affordances. VoiceOver has proper source/output naming, actual byte counts, warnings and distinct "Save copy" versus "Review original" actions.

## 8. Media matrix and negative tests

Required cases: H.264 baseline/HEVC in SDR; 4K HEVC HDR with metadata loss risk (reject initially); portrait rotation; variable-frame-rate; multiple audio tracks; muted track; damaged trailer; original uploaded to iCloud but not local; insufficient free disk mid-export; canceled Photos creation prompt; failed Photos refetch; app killed during export/after save; a derivative identical in appearance but wrong duration; dynamic range changed; output larger than source; metadata changed during export; already protected original; duplicate temp cleanup; user creates album during save. Test multiple codec and hardware device families, not just simulator.

Test suite must include an injected fake exporter for deterministic stages, a genuine AVFoundation export instrumented on physical iPhone and iPad, and a disposable Photos library integration test that confirms the original still exists after every failure. Human device acceptance needs visual HDR/color/audio spot checks where supported. The legal/metadata review must document which fields are preserved and not preserved. A codec is supported only if runtime `capability` verification passes and end-to-end source-class tests exist.

## 9. Gherkin acceptance

```gherkin
Scenario: Canceling export cannot remove the source
 Given a local video and a compression trial in progress
 When the user cancels or the process is killed
 Then the source Photos asset remains untouched
 And no source deletion entry appears in the tray

Scenario: A new file is not yet verified in Photos
 Given a completed validated export
 When Photos creation reports success but the created asset cannot be refetched
 Then the job becomes uncertain
 And the original is never offered for deletion

Scenario: Video output is larger than original
 Given a 100MB source and a 125MB output
 When output validation finishes
 Then the UI says there is no useful size saving
 And the default action is Keep original

Scenario: Live Photo transform is not compression
 Given a Live Photo with separate motion resource
 When a generic compression screen attempts to process it
 Then the V1 pipeline rejects it as unsupported
 And neither motion nor original still image is modified

Scenario: User saves a validated compressed copy
 Given successful file validation and explicit Save copy confirmation
 When Photos stores and refetches the new asset
 Then the receipt says 'Copy saved; original unchanged'
 And deleting the original requires a separate existing tray review and Apple confirmation
```

## 10. Steps, monitoring and rollback

Suggested implementation path: `Core/Sources/CleanSlateCore/CompressionCapability.swift`; `App/Services/MediaCompressionEngine.swift`; `App/Services/CompressionJobJournal.swift` (through `LibraryStore` actor); `App/Services/PhotoKitAssetCreator.swift` (separate *create*, never delete); `App/Views/CompressionLabView.swift`; `App/Views/iPad/CompressionWorkspace.swift`; `iOSTests/CompressionTransactionTests.swift`; `UITests/CompressionLabUITests.swift`.

Sequential commits: admission & fake API; journal migration/crash tests; actual single-file exporter; independent validator; Photos create/reconcile; iPhone trial/preview; iPad compare/job management; physical-device codec/low-disk/interrupt fault tests. Rollout under `N03CompressionEnabled=OFF`; launch only after device testing. Rollback hides new export UI while preserving jobs and existing Photos assets, and continues cleanup of its own confirmed temporary data safely. **Never** roll back by deleting already created photos.

**Proposed release gates:** zero original-deletion calls from compression service; every successful output has a valid, refetchable Photos asset; exact measured bytes shown; metadata loss disclosed; no silent iCloud downloads; crash-recovery cases proven; low-disk tests pass; Real-device HDR/audio review documented. No global percent-accuracy or "lossless" wording without proof.

**Sources:** https://developer.apple.com/documentation/AVFoundation/AVAssetExportSession ; https://developer.apple.com/documentation/photos/phimagemanager/requestexportsession%28forvideo%3Aoptions%3Aexportpreset%3Aresulthandler%3A%29 ; https://apps.apple.com/us/app/cleanmy-phone-cleanup-storage/id1277110040 ; https://apps.apple.com/us/app/cleansmith-photo-cleaner/id926090192


## Additional edge-case matrix

Test supported preset missing after OS update; output file with valid container but missing final audio; file created at temporary URL and then purged by storage pressure; low disk discovered *after* user requests Save copy; source photo simultaneously edited in Photos; an existing local file with same name; interrupted BackgroundTasks request; iCloud Photo library optimize mode resulting in different physical free-space delta; output photo created but Photos index not yet visible; app terminated while system creation prompt is showing; user deletes the source manually in Photos during export; and a Photos library mutation that succeeded locally but has not yet synced to iCloud. In every case the original remains untouched by the compression feature and the journal records an honest incomplete/uncertain state.
