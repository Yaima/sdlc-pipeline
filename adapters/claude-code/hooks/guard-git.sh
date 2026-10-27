#!/usr/bin/env bash
# PreToolUse hook for Bash. Keeps merge in human hands and blocks destructive commands.
# Exit 2 = deny with reason on stderr. Exit 0 = allow.
set -u
INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

CFG="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}/docs/pipeline/pipeline.json"; [ -f "$CFG" ] || CFG="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}/.claude/pipeline.json"
PROTECTED="main master"
if [ -f "$CFG" ]; then
  PROTECTED=$(jq -r '.protected_branches[]? // empty' "$CFG" | tr '\n' ' ')
fi

deny() { echo "guard-git: $1" >&2; exit 2; }

# 0. Commit mode. In "human" mode (default) agents never commit or push; the user does.
MODE="human"; [ -f "$CFG" ] && MODE=$(jq -r '.commit_mode // "human"' "$CFG")
if [ "$MODE" != "agent" ]; then
  printf '%s' "$CMD" | tr -s '[:space:]' ' ' | grep -Eq '\bgit (commit|push|merge|rebase|cherry-pick|am|tag)\b|\bgh pr (create|merge)\b|\bglab mr (create|merge|approve)\b' \
    && deny "commit_mode=human: the user commits and pushes. Leave changes in the working tree and report which files changed."
fi

# Normalize whitespace for matching
C=$(printf '%s' "$CMD" | tr -s '[:space:]' ' ')

# 1. Merging or squashing a PR is a human action.
echo "$C" | grep -Eq '\bgh pr merge\b|\bglab mr merge\b|\bglab mr approve\b' && deny "PR/MR merge and approval are human actions. Open the PR/MR and stop."

# 2. Pushing to a protected branch (explicit ref or while checked out on one).
if echo "$C" | grep -Eq '\bgit push\b'; then
  for b in $PROTECTED; do
    pat=$(printf '%s' "$b" | sed 's/\*/.*/g')
    echo "$C" | grep -Eq "\bgit push\b.*[[:space:]:]${pat}(\s|$)" && deny "push to protected branch '$b' denied"
  done
  cur=$(git -C "${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  for b in $PROTECTED; do
    pat=$(printf '%s' "$b" | sed 's/\*/.*/g')
    if [ -n "$cur" ] && echo "$cur" | grep -Eq "^${pat}$"; then
      # Bare push (no refspec) pushes the current, protected, branch.
      args=$(printf '%s' "$C" | sed -E 's/.*\bgit push\b//' | tr ' ' '\n' | grep -Ev '^(-.*|)$' | wc -l)
      [ "$args" -le 1 ] && deny "you are on protected branch '$cur'; push from a feature branch"
    fi
  done
  echo "$C" | grep -Eq '\bgit push\b.*(--force|-f\b|\+[[:alnum:]])' && deny "force push denied"
fi

# 3. Merging into a protected branch locally.
if echo "$C" | grep -Eq '\bgit (merge|rebase)\b'; then
  cur=$(git -C "${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  for b in $PROTECTED; do
    pat=$(printf '%s' "$b" | sed 's/\*/.*/g')
    [ -n "$cur" ] && echo "$cur" | grep -Eq "^${pat}$" && deny "merge into protected branch '$cur' is a human action"
  done
fi

# 4. History rewrites and resets that lose work.
echo "$C" | grep -Eq '\bgit (reset --hard|checkout -- \.|clean -f|branch -D|push --delete)\b' && deny "destructive git command; ask the user"

# 5. rm -rf outside an obvious scratch path: ask instead of deny.
if echo "$C" | grep -Eq '\brm -[a-zA-Z]*r[a-zA-Z]*f|\brm -[a-zA-Z]*f[a-zA-Z]*r'; then
  if ! echo "$C" | grep -Eq 'rm -[a-zA-Z]+ +(\./)?(node_modules|dist|build|target|\.cache|tmp|/tmp)'; then
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:"recursive delete outside build/cache paths"}}'
    exit 0
  fi
fi

exit 0
