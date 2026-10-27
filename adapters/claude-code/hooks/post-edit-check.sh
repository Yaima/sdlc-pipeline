#!/usr/bin/env bash
# PostToolUse hook for Edit|Write. Runs format and lint on the touched file if the repo configured them.
# Never blocks. Prints lint output so the agent sees it in context.
set -u
INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE" ] && exit 0
CFG="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}/docs/pipeline/pipeline.json"; [ -f "$CFG" ] || CFG="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}/.claude/pipeline.json"
[ -f "$CFG" ] || exit 0

# Skip docs and config
case "$FILE" in
  *.md|*.json|*.yml|*.yaml|*.txt) exit 0 ;;
esac

EXT=".${FILE##*.}"
FMT=$(jq -r --arg e "$EXT" '.languages[$e].format_cmd // .format_cmd // empty' "$CFG")
LINT=$(jq -r --arg e "$EXT" '.languages[$e].lint_cmd // .lint_cmd // empty' "$CFG")

cd "${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}" || exit 0

if [ -n "$FMT" ]; then
  # {file} placeholder is optional
  run=${FMT//\{file\}/$FILE}
  bash -c "$run" >/dev/null 2>&1 || true
fi

if [ -n "$LINT" ]; then
  run=${LINT//\{file\}/$FILE}
  out=$(bash -c "$run" 2>&1 | tail -n 40)
  rc=${PIPESTATUS[0]:-0}
  if [ -n "$out" ] && [ "$rc" -ne 0 ]; then
    echo "lint ($EXT) reported issues after editing $FILE:"
    echo "$out"
  fi
fi
exit 0
