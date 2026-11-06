#!/usr/bin/env bash
# The duplicate-flow policy (validateCommit) and the keeper-less policy (validateStandalone)
# must never be mixed up: each may be called from exactly one function in the app, and there
# must be exactly one PhotoKit deletion call.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
check() { # policy function name, enclosing function signature (plain text)
  local name="$1" encl="$2"
  local outside
  outside=$(grep -rn "SafetyPolicy.$name(" App | grep -v "^App/Debug" | grep -v "App/Services/PhotoDeletionCoordinator.swift" || true)
  if [[ -n "$outside" ]]; then echo "$name called outside the coordinator:"; echo "$outside"; fail=1; fi
  if ! awk -v encl="$encl" -v name="SafetyPolicy.$name(" '
      index($0, "func commit(") || index($0, "func commitStandalone(") { current = $0 }
      index($0, name) { found = 1; if (!index(current, encl)) bad = 1 }
      END { if (!found || bad) exit 1 }' App/Services/PhotoDeletionCoordinator.swift; then
    echo "$name must be called (only) inside $encl"; fail=1
  fi
}
check validateCommit "func commit("
check validateStandalone "func commitStandalone("
n=$(grep -rn "deleteAssets" App | wc -l | tr -d ' ')
if [[ "$n" -ne 1 ]]; then echo "expected exactly one deleteAssets call, found $n"; fail=1; fi
exit $fail
