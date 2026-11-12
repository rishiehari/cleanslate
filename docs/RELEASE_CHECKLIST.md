# Release checklist (updated 2026-11-11). NOT release-ready.

Current work and review status: [PROGRESS.md](PROGRESS.md). Dated validation entries remain the source of measured evidence; a historical pass does not certify the current working tree.

| Gate | Status | Evidence / note |
|---|---|---|
| Core tests (Linux/macOS) | PASS | 115/115 independently rerun on macOS 2026-11-11; Linux current revision not rerun this session |
| iOS unit + UI on simulator | **CURRENT FEATURE RUN PENDING** | Prior per-step evidence is in VALIDATION_LOG; the older 2026-11-06 full run hung before test launch. PROGRESS records later F03 unit evidence. New Swipe n Save regression evidence will be recorded separately; do not treat old results as a current full pass. |
| Design-system lint, policy-separation guard | PASS | `make lint` |
| Synthetic eval canary | PASS | `make eval`, docs/ML_GATE.md |
| Scale (252k fake assets, simulator) | HISTORICAL PASS | 130.7 s, +178 MB, thumbnails OFF; not current review+scan memory evidence and NOT measured on a device |
| F02 diagnostics log (heartbeat, stall, watchdog, MetricKit) | SIMULATOR-VERIFIED | unit tests green incl. rotation, 1,000-record concurrency, and the acceptance leak test (DiagnosticsLeakTests: full recent100 fake-scan export byte-searched for ids, filenames, capture dates + JSON-key allow-list); owner device run on the 17 Pro (F02 definition of done) NOT DONE — it is what confirms/rejects H1–H4 |
| F03 stability | DEVICE GATE PENDING | Simulator fixes/review recorded in PROGRESS and VALIDATION_LOG. Owner 17 Pro + lower-tier device, ≥7,000 items, diagnostics and Instruments still required; synchronous real PhotoKit metadata reads remain a risk |
| Swipe n Save (S01) | IN PROGRESS | Minimal directly compared two-photo similar review; new tests and independent reviews pending |
| iPad / expanded swipe onboarding and calibration | PLANNING ONLY | Requirements in docs/plans; no iPad or personalization implementation |
| Device runs (Steps 1,3,4,7,8 gates) | **NOT DONE** | needs owner + disposable library |
| Real-library scan-only run | **NOT DONE** | Instruments report needed |
| Background tasks | **NOT VERIFIED** | simulator unsupported |
| Safety changes (3.3 flag split, 4.5 standalone policy) | **OWNER REVIEW PENDING** | commits 1eb00cb, 882c276 |
| 8.4 album transfer | DEFERRED | albums stay always-protected |
| Privacy manifest codes (UserDefaults CA92.1, DiskSpace 85F4.1) | **UNVERIFIED** | Apple page could not be read; confirm against developer.apple.com |
| Export compliance (`ITSAppUsesNonExemptEncryption=false`) | **UNVERIFIED** | only CryptoKit hashing; confirm in App Store Connect |
| App icon | PLACEHOLDER | owner must approve/replace |
| Privacy policy / support pages | DRAFT | `site/`, owner must host and fill contact |
| App Store metadata | DRAFT | `fastlane/metadata/en-US` (URLs are placeholders) |
| String catalog | stub only | English only |
| Accessibility audit | PARTIAL | Home, Review and Diagnostics have historical coverage (Diagnostics has a documented narrow artifact exemption); current Swipe screens and broader inventory need evidence |
| Name/bundle ID availability, Developer account, TestFlight | **OWNER** | |
| TestFlight >= 14 days, >= 15 testers, 0 harmful reports | NOT STARTED | |
| Near-duplicate pre-selection | OFF (keep) | docs/ML_GATE.md |

### iPad implementation (2026-11-11 start)

- [x] Universal target and explicit single-window configuration; adaptive shell foundation and Compare panes implemented.
- [ ] Resolve existing app compile failures; run new layout/rotation tests and full phone regression suite.
- [ ] Finish shared routes, persistent review queue, secondary layouts, input parity and memory validation from IPAD_APP_PLAN.md.
- [ ] Capture small/medium/large iPad simulator layout/accessibility evidence and owner physical-iPad evidence. All existing iPhone/F03 gates remain pending.

### 2026-11-12 bounded-first-scan checkpoint

- [x] Integrated simulator and unsigned physical-device target builds pass.
- [x] Metadata-only activity overview and selected date/count bounds implemented; product scans capped at 2,000.
- [x] Core/fixtures/eval/lint, broad iOS unit rerun, scoped/cancellation tests, separate watchdog and tier-M memory suite have passing evidence in VALIDATION_LOG.md.
- [ ] Remaining Home/Swipe accessibility audit reconciliation and fully integrated green CI on the final checkpoint.
- [ ] Owner physical iPhone/iPad run, PhotoKit metadata latency/cancellation and Instruments evidence; actual signing/install is owner work.
- [ ] Premium-parity implementation queue: report imported and N05 specified; no feature-complete/release claim.
