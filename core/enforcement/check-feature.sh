#!/usr/bin/env bash
# Usage: check-feature.sh <slug>   Run in CI on merge requests. Exit 1 unless the feature is mergeable by the pipeline's rules.
set -u
SLUG="${1:?usage: check-feature.sh <slug>}"
ROOT=$(git rev-parse --show-toplevel); D="$ROOT/docs/features/$SLUG"; HERE=$(cd "$(dirname "$0")" && pwd)
[ -d "$D" ] || { echo "check-feature: no docs/features/$SLUG" >&2; exit 1; }
fail=0; say() { echo "check-feature: $1" >&2; fail=1; }
want=$(jq -r '.spec_sha // ""' "$D/state.json"); have=$(git hash-object "$D/spec.md" 2>/dev/null)
[ "$want" = "$have" ] || say "spec_sha in state.json ($want) != git hash-object spec.md ($have): spec changed after pinning"
last=$(grep -E '^VERDICT:' "$D/review-log.md" 2>/dev/null | tail -1)
[ "$last" = "VERDICT: APPROVE" ] || say "last review verdict is '${last:-none}', need VERDICT: APPROVE"
grep -q '^QA: PASS' "$D/qa-report.md" 2>/dev/null || say "qa-report.md lacks 'QA: PASS'"
"$HERE/check-evidence.sh" "$D/review-log.md" || fail=1
"$HERE/check-evidence.sh" "$D/qa-report.md" || fail=1
grep -qE '^- \[ \] T[0-9]+' "$D/tasks.md" 2>/dev/null && say "tasks.md has unchecked tasks"
[ $fail -eq 0 ] && echo "check-feature: $SLUG is mergeable" 
exit $fail
