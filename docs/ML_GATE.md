# ML gate — when may CleanSlate pre-select a non-identical photo for deletion?

**Decision for v1.0: never.** Only byte-identical copies (full resource sets proven equal, rechecked at the moment of
deletion) are ever pre-marked, and even those need the user's approval and Apple's confirmation. Everything else
(similar shots, bursts, videos, screenshots, large files) is chosen by the person, photo by photo.

## What would have to be true before this changes
`PreselectionConfiguration.nearEnabled && independentSafetyGatePassed` may only be switched on, by a signed-off code
change (not a remote flag, not a setting), when ALL of these hold on **held-out, independently labeled** data:

1. **Harmful-suggestion upper bound < 0.1% at 95% confidence.** A "harmful suggestion" = a photo the model would
   pre-select for removal that a human labeled as containing something unique (a different face or expression, text, a
   different moment). Computed with the exact one-sided Clopper–Pearson bound in `SafetyStatistics`.
   With zero failures that needs **≥ 2,995 independent opportunities** (`oneSidedUpperBound(0, 2995) ≈ 0.001`).
2. **Opportunities must be independent.** The unit is one *group* (one scene/moment), not one frame. Sibling frames of the
   same burst count once. Repeated sampling of the same event doesn't add evidence.
3. **Population coverage.** The held-out set must include people of varied skin tones, ages and group sizes, low light,
   RAW/ProRAW, Live Photos, screenshots, documents and text-heavy scenes, and photos from ≥ 20 different people's libraries.
4. **Calibration.** Predicted redundancy probabilities must be calibrated on a different split than the one used to
   choose the threshold (reliability curve + expected calibration error reported).
5. **Failure analysis.** Every false positive reviewed by hand; any pattern (e.g. "closed eyes", "shared text") gets its
   own hard gate (`uniqueContentDetected`) before the threshold is raised.
6. **Reversibility.** Deleted items remain in Recently Deleted for 30 days; the UI must say so at the moment of approval.

## Evidence so far (2026-11-06)
| Data | Size | Result |
|---|---|---|
| Synthetic fixtures (authored, `fixtures/`) | 8 variants × N scenes | Used ONLY as a regression canary: 0 unique-content variants reach the Exact tier. **Not evidence of real-world accuracy.** |
| Real labeled groups | **0** | The labeling tool exists (DEBUG/TestFlight "Label mode"); no data collected yet |

So the current upper bound is **uninformative (100%)** and near-duplicate pre-selection stays **off**.

## How the evidence will be gathered
Label mode (hidden switch) lets a tester mark each photo in a group `redundant`, `unique:people`, `unique:expression`,
`unique:text`, `unique:moment` or `unsure`, and which one is the best shot. Export is derived numbers only (salted hashes
of IDs, hash/feature distances, quality signals, flags, labels): **no images, no identifiers, no locations**.
`cleanslate-eval` computes recall, precision, the harmful-suggestion bound and best-shot agreement from that export.
