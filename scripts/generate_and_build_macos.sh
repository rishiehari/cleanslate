#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then echo "Requires macOS with Xcode; current system is $(uname -s)"; exit 2; fi
if ! xcode-select -p >/dev/null; then echo "Install Xcode and select it with xcode-select"; exit 2; fi
if ! command -v xcodegen >/dev/null; then
    echo 'Install XcodeGen with: brew install xcodegen'
    exit 2
fi
swift test --package-path Core
xcodegen generate --spec project.yml
xcodebuild -project CleanSlate.xcodeproj -scheme CleanSlate -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
