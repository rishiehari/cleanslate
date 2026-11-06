#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then echo 'Run on macOS with Xcode'; exit 2; fi
python3 fixtures/generate_synthetic_photos.py --out /tmp/cleanslate-fixtures --scenes 6
find /tmp/cleanslate-fixtures -type f \( -name '*.jpg' -o -name '*.png' \) -print0 | xargs -0 -n 20 xcrun simctl addmedia booted
printf '\nSynthetic test photos imported into booted simulator. Do not run deletion tests on a personal photo library.\n'
