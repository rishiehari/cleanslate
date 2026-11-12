# Mandatory Mac, simulator and physical iPhone validation

**Until all destructive-path gates pass, use a disposable Photos library only.** Unit tests passing on Linux do not validate PhotoKit integration. Keep the build private/TestFlight internal while safety evidence is incomplete.

## Build and permissions

1. Run `./scripts/generate_and_build_macos.sh` on a recent Xcode environment. Verify that `NSPhotoLibraryUsageDescription` is included in the generated app plist and read-write Photos requests appear only after user action.
2. Run `CleanSlateTests` on simulator; record the documented Vision hardware skip and any SDK availability differences. Verify Vision on a physical test device; a simulator skip is not a device pass.
3. Test Photos `.authorized`, `.limited`, `.denied`, `.restricted`, and revoke-while-scanning; check UI always reports coverage correctly.
4. Import synthetic photos using `./scripts/seed_simulator.sh` and compare exact originals, re-encoded variations, manipulated text, changed subjects and changed expressions.
5. Test no network permission and iCloud-only originals. `completeDigests` must fail safely; never mark an asset exact because of missing hashes.

## Deletion canary tests

- Two byte-identical assets with no flags: keeper survives, only reviewed duplicate can be selected, system confirms, then deletion reconciles.
- Favorites, user-picked bursts, curated albums and shared-source photos stay protected. RAW/edited/Live and other conditional flags remain blocked for similar or standalone deletion; the implemented exact-equality exception requires matching conditional keeper flags and complete resource equality. The historical Step 3 safety change still needs owner review; see RELEASE_CHECKLIST.
- Three images A~B and B~C but A not~C: do not combine into an automatically deletable group.
- Asset disappears, edits or becomes favorited after recommendation and before approval: commit aborts.
- The selected ID equals keeper ID, missing keeper, empty selection: commit aborts.
- Native Photos deletion denied or canceled: no success receipt.
- App backgrounded during hashing, app force-quit during deletion, repeated tap: no duplicate mutations and no false success.
- Limited-library membership changes: cannot count photo disappearance as confirmed deletion.
- Cloud shared library, iCloud Photos enabled, multiple devices: explicitly explain deletion effects; measure only observed outcomes.

## Scale and reliability (NOT YET PASSING)

- 10k, 50k, 100k and 250k asset metadata inventory / incremental resume; bounded 1500-25k preview does not satisfy full-library goal.
- Peak memory, 30min scan energy, storage overhead, background suspension, thermal stress and cancellation races.
- Avoid redundant full-size reads; ensure no unintentional cellular downloading of cloud-only originals.
- Quantify retrieval Recall@50 and near-duplicate safety on held-out real-photo fixtures.
- The preselection upper-bound gate of <0.1% harmful selection must be calculated on independent labeled opportunities, not sibling frames masquerading as independent.
- Validate bundle icons, privacy manifest, in-app copy, export compliance, App Store screenshots and support URL before submitting.

## Acceptance evidence template

The rows below are the original device-evidence template, not current simulator status. Record actual runs in
`VALIDATION_LOG.md`; current pending gates are tracked in `PROGRESS.md` and `RELEASE_CHECKLIST.md`.

| Gate | Result | Evidence | Reviewer |
|---|---|---|---|
| Core tests | PASS (Linux) | `swift test --package-path Core` | Local harness |
| iOS compile | NOT TESTED | Xcode build log required | — |
| iOS XCTest | NOT TESTED | Simulator results required | — |
| PhotoKit deletion canaries | NOT TESTED | Fixture-only manual run | — |
| False-delete rate | NOT TESTED | Held-out labeled evaluation | — |
| 250k scale | NOT TESTED | Instrumented device run | — |
| TestFlight/App Store | NOT SUBMITTED | ASC build IDs | — |
