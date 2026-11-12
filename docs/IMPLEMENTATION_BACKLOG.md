# Ordered next implementation milestones, with hard exit conditions

Historical initial backlog. For current sequence and measured status, use [PROGRESS.md](PROGRESS.md),
[IMPLEMENTATION_ORDER.md](IMPLEMENTATION_ORDER.md), and dated [VALIDATION_LOG.md](VALIDATION_LOG.md) entries.
The Linux-only environment and uncompiled-app statements below describe the original baseline, not current status.

## M1: compile native application on macOS (blocking)
- Install XcodeGen, generate and compile `.xcodeproj`; correct any SDK-level API errors.
- Execute `iOSTests` in CI. Do not publish signed binaries until this gate passes.
- Confirm iPhone simulator permissions and the OS deletion dialog on synthetic images.

## M2: photo library fidelity / deletion safety
- Check `PHAssetResource` exact-resource semantics against HEIC, Live, RAW, ProRAW, edits and duplicates with different metadata. Protect uncertain cases.
- Review all Photos change callback, cancellation, iCloud/no-network and OS confirmation interleavings. Add integration mocks.
- Determine how to disclose/handle iCloud Shared Library ownership and other devices. Never equate PhotoKit resources with personal billable iCloud quota.
- Add privacy and accessibility audit; verify device tests pass.

## M3: resumable 250k-asset engine
- Replace bounded scan with paginated, checkpointed SQLite metadata inventory, incremental PhotoKit change tracking, temporal/geospatial bucket retrieval and persisted feature embeddings.
- Stream resource reads under budget; per-asset cancellation, retries for non-destructive reads, cache versions, thermal and memory pressure limits.
- Add Bounded ANN index or LSH for across-year near matches; ensure candidate Recall@50 >=95% on independent labeled sets.
- Never block useful results on exhaustive iCloud downloads; report coverage per stage.

## M4: accurate best-shot / multiple keepers
- Implement normalized Vision face quality/aesthetic/sharpness/exposure ranking with human-rated learning-to-rank calibration.
- Implement conservative burst grouping with unique-expression, face coverage, OCR and semantic novelty gates; preserve several keepers per group.
- Capture explicit labels for which distinct moment should survive; validate subgroup diversity and calibrated abstentions.

## M5: optional downloadable on-device models
- Compare Apple Vision-only against small commercially redistributable Core ML embeddings on held-out data, energy and memory.
- On iOS 26+ evaluate Apple Hosted Background Assets for model delivery; no model needed on earlier devices.
- Opt-in Apple Foundation Models use only for ambiguous explanation, gated on supported OS and devices; never let it authorize deletion.

## M6: final release
- Build App Store icon, metadata, privacy policy, release notes and support URL. Icon placeholder exists; human review needed.
- Run CI on macOS, create TestFlight release with fastlane, complete device matrix, invite internal reviewers.
- Keep public App Store submission and release human gated. Monitor crash reports manually through App Store Connect; no third-party user data tracking.

## Outstanding blockers to a production claim
The initial validation machine was Linux and lacks Xcode. Therefore native type-checking, code signing, iPhone runs and actual App Store publication are not yet verified. The project source, CI configuration, test suite and macOS build instructions are real, but the application is not an externally verified release candidate.
