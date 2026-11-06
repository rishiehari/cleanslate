#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v swift >/dev/null; then echo 'Swift compiler not found'; exit 2; fi
swift test --package-path Core
swiftc -frontend -parse $(find App -name '*.swift' | sort)
python3 -m unittest discover -s fixtures -p 'test_*.py'
python3 - <<'PY'
from pathlib import Path
import plistlib
with (Path('App/Resources/PrivacyInfo.xcprivacy')).open('rb') as f:
    manifest = plistlib.load(f)
assert manifest['NSPrivacyTracking'] is False
print('Privacy manifest syntax check passed')
PY
echo 'VERIFIED: cross-platform core tests, iOS Swift syntax, fixture tests, privacy plist.'
echo 'NOT VERIFIED: iOS type checking, simulator integration or real-device behavior (requires Xcode).'
