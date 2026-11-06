# CleanSlate — completely free, private iOS photo cleanup

Native iOS SwiftUI prototype. All duplicate search and best-shot ranking runs on your iPhone using PhotoKit, Vision and a local SQLite feature cache. There is **no backend, account, subscription, ad, or photo upload**.

**Status:** The Swift core was verified with **30 passing tests on Linux**. iOS Xcode builds, simulator tests and destructive PhotoKit operations are **not yet independently verified**. Do not test deletion against personal/iCloud-synchronized libraries.

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
- `App/Services/PhotoCatalog.swift`: PhotoKit permissions, inventory, local thumbnails and streamed resource hashes.
- `App/Services/CleaningViewModel.swift`: bounded on-device scan, exact matches and manual-review near duplicates.
- `App/Services/PhotoDeletionCoordinator.swift`: fresh library-state checks, exact resource rehashing, OS-confirmed deletion and reconciliation.
- `App/Views/`: dashboard, image comparison and selected deletion review.
- `fixtures/`: deterministic mock photo scenarios.
- `.github/workflows/build.yml`: Linux Swift tests, macOS simulator build and iOS XCTest.

**Safety:** Near-duplicate matching is experimental and never preselected automatically. Photos deleted with iCloud Photos enabled also disappear from synced devices. Reported file bytes are not guaranteed recovered quota or phone free space.

## Known limitations

- Initial inventory is a bounded preview (1,500 assets; up to 25,000 through Scan More). Not a 250,000-image production scan.
- Cloud-only originals are not downloaded. No claim of exhaustive duplicate detection.
- Best-shot ranking is heuristic, not human-calibrated.
- App Store icon is not yet included in the GitHub import; simulator build can proceed without it, production builds require a validated 1024×1024 icon.
- Production signing, TestFlight and public release require additional work and review.

## Next steps

Read [device test plan](docs/DEVICE_TEST_PLAN.md) and [engineering backlog](docs/IMPLEMENTATION_BACKLOG.md). If GitHub Actions fails, share the failing macOS job log so the source can be patched. Keep any signing keys, real photos and private datasets out of GitHub.

MIT licensed. The app is intended to be free forever, but public App Store distribution normally requires the developer's Apple Developer Program membership.
