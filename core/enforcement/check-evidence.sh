#!/usr/bin/env bash
# Usage: check-evidence.sh <report file>  (review-log.md, qa-report.md, or any role report saved to a file)
# Exit 1 if the report lacks proof of work per docs/pipeline/rules/grounding.md.
set -u
F="${1:?usage: check-evidence.sh <file>}"; [ -f "$F" ] || { echo "no such file: $F" >&2; exit 1; }
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CFG="$ROOT/docs/pipeline/pipeline.json"; [ -f "$CFG" ] || CFG="$ROOT/.claude/pipeline.json"
TEST_CMD=$(jq -r '.test_cmd // ""' "$CFG" 2>/dev/null)
missing=()
grep -q '^## Evidence' "$F" || missing+=("a '## Evidence' section")
[ -n "$TEST_CMD" ] && { grep -Fq "$TEST_CMD" "$F" || missing+=("the test command from pipeline.json ($TEST_CMD) verbatim"); }
SEC_CMD=$(jq -r '.security_cmd // ""' "$CFG" 2>/dev/null)
case "$F" in *review-log*) [ -n "$SEC_CMD" ] && { grep -Fq "$SEC_CMD" "$F" || missing+=("the security command from pipeline.json ($SEC_CMD) verbatim"); } ;; esac
grep -Eiq 'exit( code)?[: ]+[0-9]+|→ [0-9]+ *\(|\| *[0-9]+ *\|' "$F" || missing+=("an exit code")
case "$F" in
  *review-log*) grep -Eq '^VERDICT: (APPROVE|CHANGES_REQUESTED|BLOCKED)' "$F" || missing+=("a VERDICT line")
                grep -Eq '^Tree: [0-9a-f]{40}$' "$F" || missing+=("a 'Tree: <hash>' line from docs/pipeline/enforcement/tree-hash.sh") ;;
  *qa-report*)  grep -Eq '^QA: (PASS|FAIL|BLOCKED|NOT READY)' "$F" || missing+=("a QA line")
                grep -Eq '^Tree: [0-9a-f]{40}$' "$F" || missing+=("a 'Tree: <hash>' line from docs/pipeline/enforcement/tree-hash.sh") ;;
esac
if [ ${#missing[@]} -gt 0 ]; then
  echo "check-evidence: $F is missing: ${missing[*]}" >&2; exit 1
fi
echo "check-evidence: $F ok"
