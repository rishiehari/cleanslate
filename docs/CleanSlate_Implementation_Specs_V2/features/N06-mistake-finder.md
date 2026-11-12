# N06 — Mistake Finder: evidence-based blur, exposure and tiny-image review

**Priority:** after screenshot intelligence. **Effort:** M, ~10–18 engineer-days plus ranking evaluation. **Premium analogues:** CleanMyPhone/Cleaner Kit blur categories and Cleansmith low-resolution/closed-eye marketing. **Hard boundary:** do not advertise reliable "closed eyes" or "bad photo" detection without a separately validated dedicated model; user taste and meaningful memories override generic technical metrics.

## 1. User problem and first-value interaction

Photos that were accidental, badly blurred, unusably dark or only tiny previews can consume space and clutter searches. A user wants a **low-confidence review queue with explanations**, not an automated machine judging whether family memories are valuable. First use before Photos permission presents a four-image demonstration: motion blur, intentionally shallow depth of field portrait, very dark exposure, sharp photo. It labels the blur and dark images "Review suggestion" and explicitly keeps the artistic portrait out of automatic mistakes. Each demo card has Why?/Keep/Review and is clearly synthetic.

With authorization, Mistake Finder analyzes a chosen scope and shows a cautious set of review packs: "Possibly blurry", "Very small", "Possibly over-/underexposed", optionally "Needs a second look". If everything is excellent or unknown, celebrate: "No obvious issues found in this scope" and direct to other value. **Never** use terms like "trash"/"ugly" as categorical quality facts. All deletion choices are manual, and suggestions never enter the tray without an explicit photo inspection and approval.

## 2. Evidence architecture

Instead of one opaque rank, compute independent technical signals:

- **Sharpness:** downscaled luminance gradient or variance of Laplacian with scale-aware normalization. Distinguish a global motion-blur pattern from low-detail scenes by checking edge count; low edge count alone is **not** proof of blur.
- **Exposure:** luminance histogram fractions near clipping; average luminance with high-dynamic-range caution; avoid marking night skies or silhouettes as mistakes solely due to darkness.
- **Resolution:** source pixel dimensions from PhotoKit, not thumbnail dimensions; flag strongly reduced copies only against device/media expectations and preserve intentional thumbnails/art.
- **Face capture quality:** Vision's quality request provides a technical indicator if supported; do not infer identity, attractiveness, emotion, eye openness or uniqueness. If no face is detectable, no face penalty.
- **Aesthetic scores:** optional tie-break/display insight only, not deletability. Do not interpret it as intrinsic artistic worth.

Each signal produces `measurement`, `validity`, `reasonCode`, `uncertainty`. A classifier eligibility gate requires multiple independently meaningful signals OR an extreme single issue with calibrated evidence; any artifact/artistic scene ambiguity triggers `reviewOnly` or `notFlagged`. There is **no automatic deletion** even for high-confidence blur. Maintain explicit issue codes, not a combined undocumented score.

```swift
enum QualityIssue: String, Codable, Sendable {
 case possibleMotionBlur, exposureClipping, lowPixelResolution,
      weakFaceCaptureQuality, insufficientEvidence
}
struct QualitySignal: Codable, Sendable {
 let issue: QualityIssue
 let metricValue: Double?
 let thresholdVersion: Int
 let validity: SignalValidity
 let reviewSuggested: Bool
}
struct MistakeFinding: Sendable {
 let assetID: String
 let revision: String
 let signals: [QualitySignal]
 let shouldAppearInReview: Bool
 let automaticRemovalAllowed: Bool // ALWAYS false
}
protocol PhotoQualityAnalyzing: Sendable {
 func analyzeThumbnail(_ image: CGImage, sourceWidth: Int,
                      sourceHeight: Int, revision: String) async throws -> [QualitySignal]
}
```

The analyzer may consume `QualitySignals` already computed by the existing `App/Services/VisualAnalyzing.swift` and keeper ranker; don't rerun full Vision work if valid cached evidence exists. Cache per asset+revision+signalVersion+inputResolution. Avoid long CPU/GPU work on the main actor; UIImage/CGImage buffers are released each batch. For low-memory tier, one photo at a time until measured proof otherwise.

## 3. Proposed persistence and state

```sql
CREATE TABLE quality_issue_cache(
 asset_id TEXT NOT NULL, revision TEXT NOT NULL, algorithm_version INTEGER NOT NULL,
 source_width INTEGER NOT NULL, source_height INTEGER NOT NULL,
 signal_payload_json TEXT NOT NULL,
 analyzed_at REAL NOT NULL,
 status TEXT NOT NULL CHECK(status IN ('ready','unavailable','failed')),
 PRIMARY KEY(asset_id,revision,algorithm_version)
);
CREATE INDEX quality_issue_status ON quality_issue_cache(status,analyzed_at);
CREATE TABLE quality_review_state(
 asset_id TEXT NOT NULL, revision TEXT NOT NULL,
 state TEXT NOT NULL CHECK(state IN ('unreviewed','kept','approved_to_tray','dismissed')),
 decided_at REAL, PRIMARY KEY(asset_id,revision)
);
```

Persist only coarse numeric signals and issue codes; no face embeddings/crops or original photos. Local explicit dismissals override future queue ordering for that revision. On a photo edit, old quality result is stale and must be recomputed; new revision must not inherit a prior deletion choice. `QualityIssue` values need stable versioning and locale-independent machine identifiers. `JSON` field requires schema version, size limit, strict decode and corrupted-row fallback.

**State machine:** `eligible → analyzing → findingsReady/unknown/noIssues → reviewChosen → kept/dismissed/trayApproved`; `pause/thermal/permissionLost/revisionChanged` can interrupt analysis, leaving a resumable cursor. An 'approved to tray' action is not deletion; only existing tray has commit authority.

## 4. iPhone UX — separate design

Home card appears only after usable signals or as a contextual demo. The category view uses three vertically stacked quality groups with actual counts within current scan coverage. Each entry's hero image is a photo plus concise reason chips: "Possible motion blur", "Very dark", "640×480 original". Tap opens Compare with nearby moment frames if a group exists, otherwise single-photo review. An intentional silhouette may be marked "Keep; this is intentional" which suppresses quality warnings for the same asset revision. A visible Why? detail explains the numeric signal in ordinary words and its limitations, e.g. "This photo has few sharp edges; intentional soft focus can look similar." Never show a bogus universal 0–100 quality truth score.

The bottom primary actions are Keep, Review later, Protect, Add to tray (only after explicit review). The app does not force a Keep/Delete binary for a solo photo. When it has a sharper nearby alternative, show both and let the human choose multiple keepers; N01 owns multi-keeper intelligence. End of session: "10 photos checked · 3 kept · 2 ready in tray · 5 skipped". Do not say "2 failures removed" before confirmation.

## 5. iPad UX — adaptive, not a stretched list

Left pane lists issue categories and counts; middle pane is a browsable grid with filter chips; right pane shows a large photo/optional alternate at a resolution suitable for seeing blur. A fixed detail panel displays each signal with confidence/limitations and a one-click Keep/Protect/Review control. Pointer hover can reveal metadata; keyboard focus changes selected photo but not approval. `K` may Keep, `P` Protect, Escape closes inspector only after shortcut conflict review; no Delete shortcut. Side-by-side comparison has linked zoom and a visible reset. Stage Manager narrow widths move categories into a sheet and detail full-screen, preserving review draft. VoiceOver reads "Possible blur (not confirmed); user review required" before actions; accessibility control order remains photo → explanation → safe actions.

## 6. Quality evaluation and difficult cases

Real-world quality tests must deliberately include artistic motion blur, bokeh portraits, dim candles, night sky, fireworks, intentional grain, screenshots, panorama, macro, animated/Live media and cropped tiny icons. Avoid bias from skin tones/face exposure; measure false suggestions across diverse lighting and faces. Develop with public-domain/self-made images, then human-label a consented representative photo sample. Annotation question: "Would you want to be *shown* this for review?" not "Should an AI delete this?" Agreement and disagreement are reported; use a reserved holdout. A person may deliberately keep a blurry photo as their only memory of an event; favorite, album, edited and user protection rules remain absolute.

Use a cost/benefit gate: feature is useful only if users find meaningful candidates at a false-alert burden that does not overwhelm; acceptance thresholds are hypotheses pending data (e.g. precision of 'worth reviewing' ≥0.8 on held-out annotation, with confidence bounds). A lower-quality photo with **no verified alternative** must never be preselected, irrespective of score. No model is trained on personal photo labels or uploaded data by default.

## 7. Functional requirements and test scenarios

```gherkin
Scenario: Artistic blur does not imply deletion
 Given a deliberately shallow-depth portrait with a soft background
 When Mistake Finder analyzes the image
 Then any warning is described as a possible issue, not a deletion fact
 And automaticRemovalAllowed is false
 And no image is staged without explicit user review

Scenario: Source resolution is independent of preview size
 Given a 4032x3024 original rendered in a 256px preview
 When resolution quality is calculated
 Then source dimensions are used
 And the photo is not called low-resolution because of the preview

Scenario: No usable quality evidence
 Given Vision and raster analysis both fail for an iCloud-only image
 When the quality review queue is refreshed
 Then its status is unknown or skipped
 And its inability to be evaluated is included in coverage

Scenario: User marks warning irrelevant
 Given a dark photo was shown as 'possibly very dark'
 When the user chooses Keep and dismiss warning
 Then the same asset revision is not re-suggested in the active review scope
 And a subsequent edit may trigger a new evidence version but not an automatic removal
```

**Fixture matrix:** full blur vs structured low-detail, tiny source vs tiny preview, intentional silhouette vs failed exposure, overexposed light source vs washed-out scene, face visible vs obstructed, mismatched color profiles, Live/RAW/adjusted, corrupted thumbnail, scene with no face. Unit metric normalization; iOS Vision fallbacks; SQL migration; batching/thermal/timeout; stale revisions; limited authorization; iPhone/iPad AX5/dark mode; device color/exposure render; end-to-end manual selection/Photos prompt cancellation with disposable library.

## 8. Performance, privacy, metrics and rollout

Reuse photo feature cache; prohibit full-resolution decode for ordinary scans. Limit quality evaluation to a scope the user explicitly initiated, with progress shown. On thermal pressure, checkpoint and pause with reason. Target one asset in flight on lowest device tier and no retained UIImage beyond iteration. Never store face images, embeddings or identification. On a low-powered device, return initial partial results rather than running an invisible 250k-asset quality audit.

Local aggregates: `qualityAssetsAnalyzed`, `reviewSuggestionsShown`, `keptFromMistakeReview`, `warningsDismissed`, `approvedToTray`, `signalUnavailableCount`. Measure helpfulness via on-device optional thumb feedback, but do not send metrics off device. Compare utility vs warning false-positive burden in supervised device tests; never show made-up accuracy badges.

Suggested commits: `N06.1` pure metrics/tests; `N06.2` bounded analysis/reuse feature cache; `N06.3` cache migration/state; `N06.4` iPhone; `N06.5` iPad; `N06.6` held-out quality test + device gates. Paths: `Core/Sources/CleanSlateCore/QualityIssue.swift`, `App/Services/MistakeFinder.swift`, `App/Views/MistakeFinderView.swift`, `App/Views/iPad/MistakeWorkspace.swift`, `iOSTests/MistakeFinderTests.swift`, `UITests/MistakeFinderUITests.swift`. Flag `N06Enabled` OFF until evaluation. Rollback deletes only rebuildable issue cache by explicit migration/maintenance, not Photos assets or real deletion receipts.

**Done:** zero silent additions to deletion tray, transparent issue reasons, meaningful no-results path, quality canaries and real-image holdout documented, Swift+UI+device budgets satisfied, iPad parity verified, no changes to safety constants.

**Sources:** https://developer.apple.com/documentation/Vision/CalculateImageAestheticsScoresRequest ; https://developer.apple.com/documentation/vision/detectfacecapturequalityrequest ; https://apps.apple.com/us/app/cleansmith-photo-cleaner/id926090192 ; https://apps.apple.com/us/app/cleanmy-phone-cleanup-storage/id1277110040
