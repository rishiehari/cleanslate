# Comprehensive tests, evaluation metrics and release gates

## 1. Test layers and exact commands

Source: observed root Makefile. On macOS with full supported Xcode and simulator:

```bash
xcode-select -p && xcodebuild -version
swift test --package-path Core
python3 -m unittest discover -s fixtures -p 'test_*.py'
make eval
make lint
make gen
make build
make ios-test
make budget BUDGET_TIER=M
```

On GitHub CI, use repository workflow and inspect actual run IDs. Do not equate a passing core test with PhotoKit integration or a simulated Vision inference skip with a hardware pass. The repository's existing `make ci` includes build/tests but does not necessarily perform device budget or on-device Photos canaries; run required gates separately. `make budget` may need a compatible iPhone SE simulator runtime; its memory model does not replace physical device sampling.

## 2. Safety mutation test fixture design

For each feature, construct injected `FakePhotoLibrary` and deterministically controlled time/task scheduler, then script these cases:

| Case | Injected event | Required behavior |
|---|---|---|
| R01 | Asset disappears after ranking | Pending removal stale; nothing deleted |
| R02 | Favorite toggled between approval and hashing | Commit blocked by fresh policy |
| R03 | Protection rule created during asynchronous digest | Commit blocked by final protection version |
| R04 | Keeper changed/removed | Target cannot proceed until new direct evidence |
| R05 | User cancels Photos prompt | No receipt of deletion; no space claim |
| R06 | Photos change request succeeds but app dies before reconciliation | Uncertain state, re-fetch, no automatic repeat |
| R07 | Limited library selection shrinks | Coverage decreases; unavailable items not reported deleted |
| R08 | Original exists only in iCloud | Default local-only; no network read; unknown reported |
| R09 | Media record has RAW, Live, edits, album protection | Conditional/hard policy remains enforced |
| R10 | One photo appears in multiple categories | Potential bytes counted once and no contradictory approvals |
| R11 | App thermal state serious | Checkpoint, visible pause, resumable cursor |
| R12 | SQL migration mid-backfill kill | Deterministic resume, no lost user protection or receipt |
| R13 | Corrupt cache/model payload | No crash; discard derived evidence, fail closed |
| R14 | iPad resize during draft, scan and tray | No duplicate work or mutation owner |
| R15 | Accessibility activation / repeated keyboard event | No duplicate approvals or surprise deletion |

The feature documents add named canaries; all apply in addition to the above. For any new PhotoKit mutation type (Favorite, album add, derivative create), add its own cancellation/uncertainty reconciliation tests. Zero direct deletion APIs outside established coordinator is a static gate.

## 3. Visual regression and human datasets

Synthetic fixtures should cover cases not present in natural datasets: one-digit screenshot change, changed QR, transitive similar graph, semantic differences in burst, same video opening with changed ending, hdr/audio drop, corrupted export, overlapping group and storage categories, and stale Photos revisions. Synthetic exact matches prove deterministic code paths, not real-world model performance.

For a human-rated consented dataset, separate train/calibration/validation/held-out test by **independent source moment**, not each frame or video as an independent example. Log collection policy, license, diversity of lighting/scene/device, annotator rubric, disagreement and exclusions. A go/no-go precision target requires an actual measured confidence interval. User preference agreement is not equal to harmful-deletion probability. Retain no private real photos in CI or public GitHub. The app's conservative deletion contract avoids auto-deletion for near matches regardless of classifier performance.

Suggested evaluation dimensions: candidate Recall@K, pair precision in "worth reviewing", calibrated uncertainty/abstention rate, multi-keeper uniqueness coverage, review throughput, false warning burden, 95% upper bound on unsafe auto-preselected exact removal opportunities, protected asset preservation, OS photo prompt integrity. Any statistic reported to users must have a defined denominator and scope.

## 4. Performance and device matrix

| Tier | Suggested reference | Must measure |
|---|---|---|
| Low supported iPhone | iPhone SE 2nd/3rd gen or iPhone 11 as supported OS permits | thermal, peak footprint, scan cancellation, AX text |
| Current iPhone | iPhone 17-class test device | Vision hardware behavior, 4K media, memory, power |
| Small iPad | iPad mini-supported OS | narrow/portrait/window resize, photo compare |
| Large iPad | iPad Pro-supported OS | side-by-side media rendering, keyboard/pointer, multitasking |

Do not claim simulated devices equal physical memory/thermal performance. Provisional engineering thresholds (subject to repository gate): main-thread stalling <250 ms, cancellation acknowledged within 2s at checkpoints, repeated 10k fake library scan retained-memory growth ≤10 MB, scan main actor work bounded, 250k-row SQLite paging with no O(N²) full comparisons. Final numeric peak memory must follow actual `DeviceTier`/`make budget` policy rather than an invented universal 300MB ceiling. Image decoder count and video frame sampling must be observable with local signposts/diagnostics.

## 5. Accessibility and multi-platform gates

Every user-visible feature: light/dark, landscape/portrait, AX3–AX5, Increase Contrast, Reduced Motion, VoiceOver, Full Keyboard Access, RTL and dynamic locale number/date format. Buttons >=44pt; never rely only on swipe/haptic/color. Real iPad tests include resizable Stage Manager narrow window, keyboard focus without accidental action, pointer hover nonmutating, and current one-window limitation. Verify simulator screenshots in repo's documented `make screens` workflow only when actual matching runner exists; record failures. Device photos and private screenshot content must never be uploaded to PR artifacts or public CI logs.

## 6. Privacy and architecture gates

Run `scripts/check_policy_separation.sh` and static scan for any new `deleteAssets` call, `URLSession`, unexpected PhotoKit network allowance, analytics SDK, background image upload or accidental raw OCR persistence. This is a code-review checklist in addition to scripted checks: a grep passing does not guarantee privacy. Inspect file data protection, backup exclusions, Keychain keys, app privacy manifest and Photos permission strings. All new models/assets must have redistributable commercial licenses verified prior to shipping; research-only pretrained weights are disallowed.

## 7. Required evidence in feature PR

- Exact HEAD SHA and diff scope, assigned migration version, user-visible feature flag default and rollback notes.
- Test results including explicit commands, exit codes, simulator/device OS and build identifiers.
- Negative-case fixture list with actual expected/observed outputs and any skipped/unavailable test.
- PhotoKit and safety review for any mutation path; code owner approval for safety changes.
- iPhone screenshots plus iPad compact/wide shots (no real personal photos).
- Performance traces for scope 100, 1k, 10k fake assets and physical device sample, with honest limitations.
- Local privacy scan; no upload/tracking endpoints; user-facing storage semantics audit.
- Definition of Done pass/fail with pending human gates clearly marked.

A green simulator build is necessary, not sufficient. Human owner must approve a TestFlight/public release independently after real-device deletion canaries and accuracy evidence.
