# Release checklist (status as of 2026-11-06). NOT release-ready.

| Gate | Status | Evidence / note |
|---|---|---|
| Core tests (Linux/macOS) | PASS | 112 tests (`swift test --package-path Core`) |
| iOS unit + UI on simulator | PASS in pieces; **full `make ci` not re-run after Steps 8-10** | one stale test fixed; run `make ci` first thing |
| Design-system lint, policy-separation guard | PASS | `make lint` |
| Synthetic eval canary | PASS | `make eval`, docs/ML_GATE.md |
| Scale (252k fake assets, simulator) | PASS | 130.7 s, +178 MB; NOT measured on a device |
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
| Accessibility audit | Home + Review only | extend to tray, history, onboarding |
| Name/bundle ID availability, Developer account, TestFlight | **OWNER** | |
| TestFlight >= 14 days, >= 15 testers, 0 harmful reports | NOT STARTED | |
| Near-duplicate pre-selection | OFF (keep) | docs/ML_GATE.md |
