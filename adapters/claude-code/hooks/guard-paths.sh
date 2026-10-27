#!/usr/bin/env bash
# PreToolUse hook for Edit|Write, attached per agent via frontmatter.
#   guard-paths.sh tests-readonly   -> deny edits to test files and protected config (implementer)
#   guard-paths.sh tests-only       -> deny edits to anything except test files (test-writer)
#   guard-paths.sh docs-only        -> deny edits outside docs/ (reviewer, analyst, retro)
# Globs come from docs/pipeline/pipeline.json (test_globs, protected_config_globs).
# Denies with permissionDecision=deny so the agent gets the reason and continues.
set -u
MODE="${1:-tests-readonly}"
# Tools without per-subagent hooks (Codex, Copilot CLI, Gemini) run one session-wide hook; SDLC_ROLE picks the mode.
case "${SDLC_ROLE:-}" in
  test-writer) MODE=tests-only ;;
  code-reviewer|requirements-analyst|architect|product-manager|estimator|retro) MODE=docs-only ;;
  implementer) MODE=tests-readonly ;;
esac
INPUT=$(cat)
# One path (Claude Code Edit/Write, Copilot, Gemini write_file/replace) or several (Codex apply_patch: paths in the patch text)
FILES=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty')
if [ -z "$FILES" ]; then
  FILES=$(printf '%s' "$INPUT" | jq -r '.tool_input.input // .tool_input.patch // .tool_input.content // empty' | grep -oE '^\*\*\* (Add|Update|Delete|Move to) File: .+' | sed -E 's/^\*\*\* [A-Za-z ]+ File: //')
fi
[ -z "$FILES" ] && exit 0
ROOT="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"
CFG="$ROOT/docs/pipeline/pipeline.json"; [ -f "$CFG" ] || CFG="$ROOT/.claude/pipeline.json"
[ -f "$CFG" ] || exit 0

check_one() {
FILE="$1"
# Path relative to repo root
case "$FILE" in
  "$ROOT"/*) REL="${FILE#"$ROOT"/}" ;;
  /*) REL="$FILE" ;;
  *) REL="$FILE" ;;
esac

match_any() {  # $1 = jq path to glob array
  local g
  while IFS= read -r g; do
    [ -z "$g" ] && continue
    # glob -> ERE: escape regex chars, then ** / ** / * via placeholders so replacements do not re-match
    local re
    re=$(printf '%s' "$g" | sed \
      -e 's/\./\\./g' -e 's/[][^$+?(){}|]/\\&/g' \
      -e 's#\*\*/#\x01#g' -e 's#\*\*#\x02#g' -e 's#\*#\x03#g' \
      -e 's#\x01#(.*/)?#g' -e 's#\x02#.*#g' -e 's#\x03#[^/]*#g')
    printf '%s' "$REL" | grep -Eq "^${re}$" && return 0
  done < <(jq -r "$1[]? // empty" "$CFG")
  return 1
}

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

is_test=0;   match_any '.test_globs' && is_test=1
is_cfg=0;    match_any '.protected_config_globs' && is_cfg=1
is_docs=0;   case "$REL" in docs/*) is_docs=1 ;; esac

case "$MODE" in
  tests-readonly)
    [ "$is_test" -eq 1 ] && deny "guard-paths: test files are read-only for this agent ($REL). If a test is wrong, record it under 'Test disputes' in docs/features/<slug>/tasks.md and stop."
    [ "$is_cfg" -eq 1 ]  && deny "guard-paths: CI, lint, and pipeline config are read-only for this agent ($REL). Report the needed change instead."
    ;;
  tests-only)
    [ "$is_docs" -eq 1 ] && exit 0
    [ "$is_test" -eq 0 ] && deny "guard-paths: this agent edits test files only ($REL is not a test path per pipeline.json test_globs)."
    ;;
  docs-only)
    [ "$is_docs" -eq 0 ] && deny "guard-paths: this agent writes only under docs/ ($REL)."
    ;;
esac
}
while IFS= read -r f; do [ -n "$f" ] && check_one "$f"; done <<< "$FILES"
exit 0
