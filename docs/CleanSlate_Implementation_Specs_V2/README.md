# CleanSlate — Premium-parity implementation specifications V2

**Prepared:** 2026-11-12. **Scope:** ten individually implementable, fully free, on-device features for iPhone and iPad. **No production code has been changed.**

This package is intended to be copied into the `rishiehari/cleanslate` repository under `docs/next-features/` (preserving these relative paths). It is a substantially more operational artifact than a market-analysis summary. Each feature has a stable identifier, typed contracts, proposed SQL, exact state transitions, phone/tablet UI requirements, failure semantics, fixtures, test cases, phased commits, and a Definition of Done. Common contracts here apply in addition to feature-specific contracts.

## Start here

1. `shared/00_REPOSITORY_BASELINE.md` — what the existing app already has, what is blocked, and what not to rewrite.
2. `shared/01_ENGINEERING_INVARIANTS.md` — all features must satisfy this safety, privacy, scale, and evidence contract.
3. `shared/02_DATA_AND_MIGRATION_STRATEGY.md` — migration ownership, cache lifetimes, crash recovery, data protection.
4. `shared/03_IPHONE_EXPERIENCE.md` and `shared/04_IPAD_EXPERIENCE.md` — separate screen architecture and interaction contracts.
5. `shared/05_FIRST_SESSION_AND_ENGAGEMENT.md` — truthful first value and private counters.
6. `shared/06_TEST_AND_RELEASE_GATES.md` — device matrix, benchmark definitions, Gherkin and adversarial tests.
7. `shared/07_DEPENDENCIES_AND_ROADMAP.md` — one-feature-at-a-time implementation order.
8. `features/Nxx-*.md` — the ten complete implementation specifications.
9. `agents/MASTER_AGENT_HANDOFF.md` — copy-ready instructions for any coding agent.

## The ten features

| ID | Name | Primary value | Relative effort | Mandatory prerequisite |
|---|---|---|---|---|
| N05 | Never Suggest / Protection Rules | Trust controls that truly block unsafe suggestions | M | safety tests, storage migration contract |
| N04 | Storage Goal Planner | A credible route toward a user-defined target | M | scoped scan/coverage and N05 |
| N07 | Screenshot Intelligence | OCR-aware repeat clutter with changed-text protection | L | scoped scan, screenshot category and N05 |
| N06 | Mistake Finder | Explain possible blur/dark/low-resolution issues | M | quality-signal calibration, N05 |
| N01 | Moment Intelligence / Best-Shot+ | Multiple keepers and meaningfully better burst review | XL | stable grouping, held-out human evaluation |
| N02 | Similar and Re-encoded Video Finder | Surface large visually redundant videos | XL | AVFoundation test corpus, resource governor |
| N03 | Compression Lab | Loss-controlled, opt-in media reduction | XL | N02 and crash-safe replacement ledger |
| N08 | Album Inbox | Fast nondestructive organization | L | permission matrix and single PhotoKit mutation coordinator |
| N09 | Rescue Gems | Rediscover value in photos worth keeping | M | calibrated quality, inclusion/diversity tests |
| N10 | Local Taste Personalization | Private queue ranking from explicit preferences | XL | all earlier safety gates, offline model ablation |

These are **implementation order**, not the numerical ranking used in the earlier research summary. Existing `F01–F10`, `S01` and the iPad work remain their own roadmaps.

## Research and claim discipline

Competitor capabilities are *advertised claims*, not reverse-engineered truth. The evidence URLs and caveats are in `shared/08_COMPETITOR_EVIDENCE.md`. All numeric thresholds in this package are proposed engineering gates or launch experiments, **not measured results**. Algorithm sketches are implementation contracts, not proven model accuracy. Never use synthetic fixtures as evidence of real-world quality.

## Build and test discipline

```sh
git clone https://github.com/rishiehari/cleanslate.git
cd cleanslate
git rev-parse HEAD
make core-test
make fixtures-test
make eval
make lint
make gen
make build
make ios-test
make budget
```

Run the repo's actual `make` targets only after checking them against `Makefile`. `make budget` requires a suitable simulator and is not a substitute for real-device memory, energy, Vision or Photos tests. Stop when an existing gate fails and record it; do not silently waive a failing gate to implement the next feature.

## What this package does not claim

It does **not** include a built app, completed feature implementation, certified safe deletion of real photos, measured model precision, or real-device validation. It does **not** authorize deletion on private/iCloud Photos libraries or a public App Store release. Apple Photos merge behavior is not available as a general third-party PhotoKit operation. All deletion still goes through the existing review, tray, system permission and commit-time validation.
