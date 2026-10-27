#!/usr/bin/env bash
# Usage: check-feature.sh <slug> [--run]   Run in CI on merge requests. Exit 1 unless the feature is mergeable by the pipeline's rules.
#   --run  also execute test_cmd, lint_cmd, typecheck_cmd, security_cmd from pipeline.json here, in this checkout. This is the
#          authoritative check: the reports are what the agents said happened; --run is what happens on this tree.
#          Use it in a CI job that has the repo's toolchain.
set -u
SLUG="${1:?usage: check-feature.sh <slug> [--run]}"; RUN=0; [ "${2:-}" = "--run" ] && RUN=1
ROOT=$(git rev-parse --show-toplevel); D="$ROOT/docs/features/$SLUG"; HERE=$(cd "$(dirname "$0")" && pwd)
CFG="$ROOT/docs/pipeline/pipeline.json"
[ -d "$D" ] || { echo "check-feature: no docs/features/$SLUG" >&2; exit 1; }
command -v jq >/dev/null || { echo "check-feature: jq is required" >&2; exit 1; }
fail=0; say() { echo "check-feature: $1" >&2; fail=1; }

# 1. Pinned documents: spec_sha (always) and the manifest written at handoff (when present)
want=$(jq -r '.spec_sha // ""' "$D/state.json"); have=$(git hash-object "$D/spec.md" 2>/dev/null)
[ "$want" = "$have" ] || say "spec_sha in state.json ($want) != git hash-object spec.md ($have): spec changed after pinning"
if jq -e '.manifest | type == "object" and length > 0' "$D/state.json" >/dev/null 2>&1; then
  while IFS=$'\t' read -r key sha; do
    case "$key" in
      ticket) f="$D/ticket.md" ;; prd) f="$D/prd.md" ;; spec) f="$D/spec.md" ;; data_model) f="$D/data-model.md" ;;
      pipeline) f="$CFG" ;; *) say "manifest has unknown key '$key'"; continue ;;
    esac
    cur=$(git hash-object "$f" 2>/dev/null || echo missing)
    [ "$sha" = "$cur" ] || say "manifest.$key ($sha) != git hash-object $(basename "$f") ($cur): changed after handoff"
  done < <(jq -r '.manifest | to_entries[] | select(.value != null) | "\(.key)\t\(.value)"' "$D/state.json")
fi

# 2. Verdicts
last=$(grep -E '^VERDICT:' "$D/review-log.md" 2>/dev/null | tail -1)
[ "$last" = "VERDICT: APPROVE" ] || say "last review verdict is '${last:-none}', need VERDICT: APPROVE"
grep -q '^QA: PASS' "$D/qa-report.md" 2>/dev/null || say "qa-report.md lacks 'QA: PASS'"

# 3. Report shape
"$HERE/check-evidence.sh" "$D/review-log.md" || fail=1
"$HERE/check-evidence.sh" "$D/qa-report.md" || fail=1

# 4. The reviewed tree is this tree. Review and QA record the hash they looked at; a different hash here means code changed after them.
now=$("$HERE/tree-hash.sh" 2>/dev/null || echo "")
[ -n "$now" ] || say "tree-hash.sh failed; cannot bind the reports to this tree"
rt=$(grep -E '^Tree: [0-9a-f]{40}$' "$D/review-log.md" 2>/dev/null | tail -1 | awk '{print $2}')
qt=$(grep -E '^Tree: [0-9a-f]{40}$' "$D/qa-report.md" 2>/dev/null | tail -1 | awk '{print $2}')
[ -n "$now" ] && [ -n "$rt" ] && [ "$rt" != "$now" ] && say "review-log.md Tree ($rt) != this tree ($now): code changed after the last review"
[ -n "$now" ] && [ -n "$qt" ] && [ "$qt" != "$now" ] && say "qa-report.md Tree ($qt) != this tree ($now): code changed after QA"

# 5. Tasks
grep -qE '^- \[ \] T[0-9]+' "$D/tasks.md" 2>/dev/null && say "tasks.md has unchecked tasks"

# 6. --run: execute the repo's commands here. The reports above are testimony; this is the check.
if [ "$RUN" -eq 1 ]; then
  for k in test_cmd lint_cmd typecheck_cmd security_cmd; do
    c=$(jq -r ".$k // \"\"" "$CFG"); [ -n "$c" ] || continue
    echo "check-feature: running $k: $c"
    (cd "$ROOT" && bash -c "$c"); rc=$?
    [ $rc -eq 0 ] || say "$k exited $rc: $c"
  done
fi

[ $fail -eq 0 ] && echo "check-feature: $SLUG is mergeable$([ $RUN -eq 1 ] && echo ' (commands run here)')"
exit $fail
