#!/usr/bin/env bash
# The duplicate-flow policy (validateCommit) and the keeper-less policy (validateStandalone) must never be
# mixed up. Each may be called ONLY from its own two functions: the real commit, and the advisory tray recheck
# that merely decides whether to show "Needs another look". There must be exactly one PhotoKit deletion call.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
check() { # policy name, allowed enclosing func signatures (separated by |)
  local name="$1" allowed="$2"
  local bad
  bad=$(for f in $(grep -rl "SafetyPolicy.$name(" App | grep -v "^App/Debug"); do
    awk -v name="SafetyPolicy.$name(" -v allowed="$allowed" -v file="$f" '
      BEGIN { n = split(allowed, ok, "|") }
      /^ {0,4}(private |fileprivate |static |nonisolated )*func / { current = $0 }
      index($0, name) {
        good = 0
        for (i = 1; i <= n; i++) if (index(current, ok[i])) good = 1
        if (!good) print file ":" NR ": " $0
      }' "$f"
  done)
  if [[ -n "$bad" ]]; then echo "$name called from a function that is not allowed to:"; echo "$bad"; fail=1; fi
  local count
  count=$(grep -rn "SafetyPolicy.$name(" App | grep -vc "^App/Debug" || true)
  if [[ "$count" -lt 1 ]]; then echo "$name is never called"; fail=1; fi
}
check validateCommit "func commit(|func reasonNeedingAnotherLook(_ entry: TrayEntry)"
check validateStandalone "func commitStandalone(|func reasonNeedingAnotherLook(_ entry: StandaloneTrayEntry)|func evaluate(groups:"
check validateBatch "func evaluate(groups:"
n=$(grep -rn "deleteAssets" App | wc -l | tr -d ' ')
if [[ "$n" -ne 1 ]]; then echo "expected exactly one deleteAssets call, found $n"; fail=1; fi
exit $fail
