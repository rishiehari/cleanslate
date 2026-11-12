# CleanSlate — completely free, private iOS photo cleanup

Native iOS SwiftUI prototype. All duplicate search and best-shot ranking runs on your iPhone using PhotoKit, Vision and a local SQLite feature cache. There is **no backend, account, subscription, ad, or photo upload**.

**Status:** Active implementation; see [current progress](docs/PROGRESS.md) and [validation evidence](docs/VALIDATION_LOG.md). The current macOS Core baseline is **115 passing tests** (2026-11-11). F01–F03 have recorded simulator validation and review; the F03 physical-device stability gate remains **PENDING**, and the app is not release-ready. Do not test deletion against personal/iCloud-synchronized libraries.

## Local Mac setup

Install Xcode and the iOS Simulator through Apple's developer tools. In Terminal:

```bash
xcode-select -p
xcodebuild -version
brew install xcodegen
git clone https://github.com/rishiehari/cleanslate.git
cd cleanslate
swift test --package-path Core
xcodegen generate --spec project.yml
xcodebuild -project CleanSlate.xcodeproj -scheme CleanSlate -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Or run `bash scripts/generate_and_build_macos.sh`. If Xcode reports an error, keep the entire error log and fix the build before attempting deletion testing.

## Simulator testing (disposable data only)

```bash
brew install python
python3 -m pip install pillow
open -a Simulator
xcrun simctl bootstatus booted -b
bash scripts/seed_simulator.sh
xcodebuild -project CleanSlate.xcodeproj -scheme CleanSlate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO test
```

The generator creates exactly identical copies as well as recompressed images, altered text, changed facial expressions and removed subjects. These are synthetic canaries, *not* proof of real-world model accuracy. Use only a disposable simulator library.

## Current architecture

- `Core/`: independently tested deterministic candidate retrieval, resource signatures, keeper ranker and fail-closed deletion policy.
- `App/Services/PhotoKitLibraryClient.swift`: PhotoKit permissions, inventory, local thumbnails and streamed resource hashes behind `PhotoLibraryClient`.
- `App/Services/CleaningViewModel.swift` and `ScanEngine.swift`: resumable on-device scan, exact matches and manual-review similar photos, backed by `LibraryStore`.
- `App/Services/PhotoDeletionCoordinator.swift`: fresh library-state checks, exact resource rehashing, OS-confirmed deletion and reconciliation.
- `App/Views/`: dashboard, image comparison and selected deletion review.
- `fixtures/`: deterministic mock photo scenarios.
- `.github/workflows/build.yml`: Linux Swift tests, macOS simulator build and iOS XCTest.

**Safety:** Near-duplicate matching is experimental and never preselected automatically. Photos deleted with iCloud Photos enabled also disappear from synced devices. Reported file bytes are not guaranteed recovered quota or phone free space.

## Known limitations

- Inventory is paged and resumable; per-pass exact verification and visual comparisons are capped. Recent-100 scope is planned in F04 and is not implemented yet. Fake-library scale results do not establish device performance.
- Default scans use local data. Original downloads require the existing opt-in, path-checked, budgeted PhotoKit verification setting. No claim of exhaustive duplicate detection.
- Best-shot ranking is heuristic, not human-calibrated.
- An app icon placeholder is included; production artwork still requires owner review.
- Production signing, TestFlight and public release require additional work and review.

## Next steps

Start with [current progress](docs/PROGRESS.md), [implementation order](docs/IMPLEMENTATION_ORDER.md), and the
[device test plan](docs/DEVICE_TEST_PLAN.md). The older engineering backlog is historical context. Detailed planning:
[iPad expansion](docs/plans/IPAD_APP_PLAN.md) and [Swipe n Save, onboarding and calibration](docs/plans/SWIPE_N_SAVE_PLAN.md).
iPad remains planning-only. Keep signing keys, real photos and private datasets out of GitHub.

MIT licensed. The app is intended to be free forever, but public App Store distribution normally requires the developer's Apple Developer Program membership.
