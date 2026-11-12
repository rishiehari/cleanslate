# Cross-feature engineering invariants

Every Nxx feature MUST satisfy these constraints. Treat them as executable acceptance requirements, not aspirational design rules.

## I-01 — Single authority for photo deletion

The only permitted user-visible flow is **Review → explicit Approve → DeletionTray → explicit Delete → system Photos confirmation → fresh reconciliation**. New features may produce review candidates; they cannot call `PHAssetChangeRequest.deleteAssets` or `PhotoLibraryClient.delete` themselves. `PhotoDeletionCoordinator.commit` remains the coordinator. Existing `SafetyPolicy.validateCommit` is applied to fresh live `AssetRecord`s, with direct evidence for each target-to-surviving-keeper relationship. A target protected by a hard safety flag never becomes deletable through a setting, personalization or storage-goal optimization. In particular, `A≈B` and `B≈C` never establish `A≈C`.

**Mandatory test:** verify that every new model's `suggestedRemovalIDs` is either empty, or only contains records whose preselection remains allowed by the shared safety policy; similar, low-quality, video and screenshot classifiers default to **manual** decisions. For a non-grouped standalone selection, use existing standalone review safety and never fabricate a keeper.

## I-02 — Revision and permissions are time-varying

All cached recommendations carry `assetID`, library revision and `algorithmVersion`. A PhotoKit change, limited-library selection change, edited asset, favorite change, album membership change, new shared-owner context or disappeared asset makes the relevant draft **stale**. Stale approvals must be re-rendered, not silently auto-repaired into a new deletion choice. Check authorization at request start, after background resume, before destructive commit and after returning from Settings.

Limited access means only user-authorized assets are visible. Do not claim coverage of the whole camera roll or enumerate/fetch user albums in this mode. Offer the system's limited-library selection management only in context.

## I-03 — Privacy, storage and offline boundaries

All inference runs on device by default. No account, upload, analytics SDK, remote config, cloud service, network telemetry or paid third-party API. Photo pixels and OCR text should be transient; no images, face embeddings, raw OCR, paths, GPS or personal identifiers in logs. Derived sensitive fingerprints should be keyed, versioned, encrypted by system data protection and easily deleted with CleanSlate local data. Keychain access material must not be exported in diagnostics.

PhotoKit originals may be unavailable locally. The default remains `allowNetwork: false`; any opt-in iCloud original download must reuse the existing `NetworkPolicy` and show expected size, cellular conditions, cancellation and budget. No feature silently turns network access on.

## I-04 — Separate four storage quantities

Maintain typed quantities (no stringly typed `Double GB` in domain models):

```swift
struct StorageEvidence: Sendable, Codable {
    let eligiblePotentialLogicalBytes: Int64?  // validated candidate resource sizes, not freed space
    let verifiedRemovedLogicalBytes: Int64?    // receipt after live Photos reconciliation
    let localFreeSpaceDeltaBytes: Int64?       // noisy OS before/after observation
    let iCloudQuotaRecoveredBytes: Int64?     // must remain nil: not reliably attributable
    let coverage: CoverageDescriptor          // indexed/verified/unknown/limited scopes
    let measuredAt: Date
}
```

Potential bytes are never called 'already freed'. Verified removal does not guarantee an immediately matching local-capacity delta: Recently Deleted, shared media, iCloud optimization and Photos storage accounting can differ. Avoid adding hypothetical compression deltas to confirmed deletions. Show coverage and unknowns prominently.

## I-05 — Resource limits and continuous feedback

No broad scan in a SwiftUI view body, PhotoKit change callback, or app launch. Work is cancellable, checkpointed and bounded; heavy media decoding uses a single active worker at the lowest device tier until real measurement permits more. Existing `ResourceGovernor` supplies thermal/memory/Low Power Mode policies; stop/retry/resume must be visible. Never retain decoded video frames across an entire batch. Every data-bound UI has loading, empty, blocked, partial, stale, cancelled and error states.

**Proposed budgets pending device measurements:** no main-thread stall over 250 ms in synthetic 10k-library tests; cancellation becomes observable within 2 s at safe checkpoints; never exceed the repo's tier-specific measured memory ceiling; no unbounded O(N²) comparisons. Do not present simulator footprint as phone physical memory evidence.

## I-06 — Single source of truth across iPad and iPhone

One app-level `PhotoLibraryClient`, `LibraryStore`, `DeletionTray`, `ResourceGovernor`, and delete coordinator. Presentation state is scene-local; mutation state is app-global. Resizing/reorientation must not create another scan or rerun approval. The iPad has its own composition, keyboard, pointer and multi-pane UX rather than a scaled phone; the same eligibility, permissions, storage and safety rules apply. Multiple independent windows remain unsupported until separately tested (current project disables multiple scenes).

## I-07 — Calibrated uncertainty

Confidence scores are not probabilities unless calibrated on representative held-out device-appropriate data. Label scores 'quality indicators' or 'possible match' until validated. No eye-open, emotion, person identity or content importance claim from an unsupported generic model. Feature gates stay OFF if accuracy evidence or physical-device hardware support is incomplete. Unknown evidence must produce review-only, skip or no-recommendation—not an optimistic deletion.

## I-08 — Release and recovery

Every stateful feature needs a crash/kill/resume test, schema upgrade test, schema rollback story, permission-revocation test, and destructive-operation audit. Any Apple Photos mutation must survive: system prompt cancellation, operation timeout, partial success/uncertain reconciliation, app process death and library change concurrent with action. Release flags are compiled defaults, not remotely controlled. Do not use 'Tests passed' for tests not executed on the exact branch.
