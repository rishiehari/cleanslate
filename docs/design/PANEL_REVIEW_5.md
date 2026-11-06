# Expert panel review — Step 5 milestone (architecture & scale), simulated by the executing agent

**Honesty note:** a structured self-review grounded in the code, the tests and the numbers measured on the simulator
(`docs/VALIDATION_LOG.md`). Not a substitute for a device run: no number below was measured on a real iPhone.

## Panel
1. **Principal iOS architect** · 2. **Performance engineer** · 3. **Deletion-safety reviewer** (adversarial)
4. **SRE / reliability** · 5. **Power user** (150k–250k photos, iCloud on) · 6. **Privacy reviewer**

## Findings and what changed
| # | Persona | Finding | Severity | Action |
|---|---|---|---|---|
| 1 | Architect | Removing the 240-pair cap exposed a real hazard: with look-alike photos the scan tried every candidate pair with Vision. In the simulator each failure takes ~0.4 s, so a test run hung for 15+ minutes | **High** | Circuit breaker: after 5 consecutive Vision failures the similar-photo stage stops, reports `visionUnavailable` and the number of skipped pairs; test added |
| 2 | Architect | Pair ranking (sort of up to 200k pairs) ran on the main actor | Medium | Moved to a detached task; ranking is a pure `nonisolated static` function with a unit test |
| 3 | Architect | `ScanEngine` is main-actor bound because PhotoKit is; CPU work (hashing images, ranking, SQL) is off-main via detached tasks and the store actor | OK | Documented in `docs/ARCHITECTURE.md` |
| 4 | Performance | Fingerprinting was the old bottleneck (serial, main thread) | High | Batches of 200 with 1–4 concurrent workers; governor lowers width when warm/low memory |
| 5 | Performance | `exactKeys()` loads one row per asset per scan (~25 MB at 250k) | Low | Accepted; measured in the scale test |
| 6 | Performance | Vision pass always re-examines the same top-ranked 30,000 pairs; lower-ranked pairs are never reached | Medium | **Known gap.** Needs a persisted "pair examined" table; deferred to Step 7/9 because it must be validated on a device |
| 7 | Safety | The index is a cache and never an authority: every deletion re-fetches from PhotoKit, re-hashes (exact) and re-runs the full policy | Critical | Unchanged and re-verified (policy separation script, coordinator tests all green after the engine rewrite) |
| 8 | Safety | Album membership is now computed once per scan as a set and stamped on snapshots; the commit step still checks per asset | Medium | Both layers kept |
| 9 | Safety | A scan that stops early (heat, Stop) leaves partial results visible | Low | Exact groups only appear after full verification, so partial results are still correct, just incomplete; the status line says "paused" |
| 10 | SRE | Kill during inventory or fingerprinting | High | Inventory resumes from `inventory.offset`; fingerprints are committed per batch (loses ≤ 200). Tests: interrupted inventory resumes; heat-stopped scan continues with only the remaining photos |
| 11 | SRE | Expired / unsupported change token | Medium | Falls back to a full inventory and marks vanished assets deleted. Tests for both |
| 12 | SRE | Migrations | Medium | Versioned (`PRAGMA user_version`), transactional, tested (reopen keeps data, runs once) |
| 13 | Power user | Second launch used to re-scan everything | High | Incremental sync via persistent change history + cached fingerprints: second scan re-reads nothing (test: no pages requested, no thumbnails) |
| 14 | Privacy | The index holds identifiers, dates, filenames and 64-bit hashes | Medium | Excluded from backup, file-protected, wiped by "Clear saved scan data"; no images stored |
| 15 | Privacy | Background tasks | Low | Only a local scan; no network except the existing opt-in iCloud checking |

## Verdict
Proceed to Step 6. Open items: persisted pair-examined cache (6 above), real-device scan-only run (human gate),
background tasks verified on a device (the simulator doesn't support them).
