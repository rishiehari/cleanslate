# CleanSlate — private, on-device photo cleanup

A native SwiftUI prototype for finding exact and near-duplicate photos using PhotoKit and Vision. All analysis runs on device; no application-owned backend.

## Status

- Swift package core tests: 30 passing on Swift 6.2.1/Linux in the development environment.
- iOS project source and CI configuration: in progress; **no native Xcode build has been verified yet**.
- Deletion workflow is experimental. **Do not test against personal photo libraries or iCloud Photos.** Use a disposable simulator library until integration testing passes.

## Development

Prerequisites: recent Xcode and iOS Simulator, Swift toolchain, Homebrew, and XcodeGen.

```sh
brew install xcodegen
xcodegen generate --spec project.yml
swift test --package-path Core
xcodebuild -project CleanSlate.xcodeproj -scheme CleanSlate -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

See `docs/DEVICE_TEST_PLAN.md` and `scripts/` for further instructions after the source import is complete.

## License

MIT. No advertisements, analytics, recurring services, or subscriptions. App Store distribution may require an Apple Developer Program membership.
