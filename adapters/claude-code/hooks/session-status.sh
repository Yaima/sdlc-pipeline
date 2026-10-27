#!/usr/bin/env bash
# SessionStart hook. Prints the operator's role, features waiting on that role, and all in-flight features.
set -u
ROOT="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"
CFG="$ROOT/docs/pipeline/pipeline.json"; [ -f "$CFG" ] || CFG="$ROOT/.claude/pipeline.json"
LOCAL="$ROOT/docs/pipeline/pipeline.local.json"; [ -f "$LOCAL" ] || LOCAL="$ROOT/.claude/pipeline.local.json"
DOCS="docs/features"
[ -f "$CFG" ] && DOCS=$(jq -r '.docs_dir // "docs/features"' "$CFG")

ROLES="solo"; NAME=""
if [ -f "$LOCAL" ]; then
  ROLES=$(jq -r 'if (.role|type)=="array" then .role|join(" ") else (.role // "solo") end' "$LOCAL")
  NAME=$(jq -r '.name // ""' "$LOCAL")
  echo "pipeline: operator ${NAME:-unnamed}, role(s): $ROLES"
else
  echo "pipeline: no docs/pipeline/pipeline.local.json; role defaults to solo. Run /start to set it."
fi

if [ -f "$CFG" ]; then
  t=$(jq -r '.test_cmd // ""' "$CFG")
  [ -z "$t" ] && echo "pipeline: test_cmd is empty in docs/pipeline/pipeline.json; set it before /implement."
fi

found=0
for s in "$ROOT/$DOCS"/*/state.json; do
  [ -f "$s" ] || continue
  found=1
  jq -r '"feature \(.slug): stage=\(.stage) round=\(.review_round // 0)/\(.max_review_rounds // 3) verdict=\(.last_verdict // "none") blast=\(.blast_radius // "?")"' "$s"
  for r in $ROLES; do
    jq -r --arg r "$r" '.handoffs[]? | select(.to_role==$r or $r=="solo") | "  waiting on \(.to_role): \(.gate) gate: \(.question)"' "$s"
  done
done
[ "$found" -eq 0 ] && echo "pipeline: no features in progress. Run /start, or /feature <slug> <idea>."
exit 0
