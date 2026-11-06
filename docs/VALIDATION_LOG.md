# Validation log

Append one entry per step using the template in `docs/EXECUTION_PLAN.md` §0.3.

## Step 1.2/1.3 findings (in progress) — 2026-11-05
- Root cause of the red simulator test: Vision feature prints throw `Failed to create espresso context` (NSOSStatusErrorDomain -1) on the iOS 26.5 simulator. Not a code bug; the old API swallowed the error as `nil`.
- Fix: migrated `VisualFeatures` to the Swift Vision API (`GenerateImageFeaturePrintRequest`, `CalculateImageAestheticsScoresRequest`, `DetectFaceCaptureQualityRequest`), now `async throws`. The feature-print test skips on the simulator with the real error text and FAILS on device.
- Consequence: near-duplicate (Vision) matching can only be exercised on a physical device. Simulator runs cover exact matching, dHash and UI.
