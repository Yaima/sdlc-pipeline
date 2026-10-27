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

# 0b. Ways around the rules below: git aliases defined inline, hook path overrides, skipping hooks.
echo "$C" | grep -Eq '\bgit\b[^|;&]*-c +alias\.' && deny "inline git alias denied; run the git command directly"
echo "$C" | grep -Eq '\bgit\b[^|;&]*-c +core\.hooksPath' && deny "overriding core.hooksPath is denied"
echo "$C" | grep -Eq '\bgit\b[^|;&]*--no-verify\b' && deny "--no-verify is denied; hooks run"
echo "$C" | grep -Eq '\bgit\b[^|;&]*\bconfig\b[^|;&]*(alias\.|core\.hooksPath|receive\.|push\.default)' && deny "changing git aliases, hook path, or push defaults is denied"

# 1. Merging or squashing a PR is a human action.
echo "$C" | grep -Eq '\bgh pr merge\b|\bglab mr merge\b|\bglab mr approve\b' && deny "PR/MR merge and approval are human actions. Open the PR/MR and stop."

# 2. Pushing to a protected branch (explicit ref or while checked out on one).
if echo "$C" | grep -Eq '\bgit push\b'; then
  for b in $PROTECTED; do
    pat=$(printf '%s' "$b" | sed 's/\*/.*/g')
    echo "$C" | grep -Eq "\bgit push\b.*[[:space:]:+](refs/heads/)?${pat}(\s|$)" && deny "push to protected branch '$b' denied"
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

# 5a. Shell writes to test files and protected config. The Edit/Write guard covers tool edits; this covers
#     rm, mv, truncate, sed -i, git rm/checkout/restore, and output redirection. Reads (cat, grep, sed -n) pass.
if [ -f "$CFG" ]; then
  glob_match() {  # $1 jq path, $2 relative path
    local g re
    while IFS= read -r g; do
      [ -z "$g" ] && continue
      re=$(printf '%s' "$g" | sed -e 's/\./\\./g' -e 's/[][^$+?(){}|]/\\&/g' -e 's#\*\*/#\x01#g' -e 's#\*\*#\x02#g' -e 's#\*#\x03#g' -e 's#\x01#(.*/)?#g' -e 's#\x02#.*#g' -e 's#\x03#[^/]*#g')
      printf '%s' "$2" | grep -Eq "^${re}$" && return 0
    done < <(jq -r "$1[]? // empty" "$CFG")
    return 1
  }
  check_write_target() {  # $1 token
    local t="$1" q="'"; t=${t#[\"$q]}; t=${t%[\"$q]}
    case "$t" in ''|-*) return 0 ;; esac
    if glob_match '.test_globs' "$t" && [ "${SDLC_ROLE:-}" != "test-writer" ]; then
      deny "shell write to test file '$t' denied for this role. Test files change through the test-writer role (SDLC_ROLE=test-writer outside Claude Code); a wrong test is a dispute in tasks.md."
    fi
    if glob_match '.protected_config_globs' "$t" && [ "${SDLC_ALLOW_CONFIG:-}" != "1" ]; then
      deny "shell write to protected config '$t' denied. Report the needed change; a person applies it (SDLC_ALLOW_CONFIG=1)."
    fi
  }
  # mutating commands: every argument token is a candidate target
  if echo "$C" | grep -Eq '(^|[;&|] *)(rm|mv|cp|tee|truncate|sed -i[^ ]*|perl -[a-z]*i[a-z]* |git (rm|checkout|restore|mv))\b'; then
    for tok in $C; do check_write_target "$tok"; done
  fi
  # redirection: the token after > or >> is the target
  prev=""
  for tok in $C; do
    case "$prev" in '>'|'>>'|'1>'|'2>'|'&>') check_write_target "$tok" ;; esac
    case "$tok" in *'>'*) tgt=${tok##*>}; [ -n "$tgt" ] && check_write_target "$tgt" ;; esac
    prev="$tok"
  done
fi

# 5. rm -rf outside an obvious scratch path: ask instead of deny.
if echo "$C" | grep -Eq '\brm -[a-zA-Z]*r[a-zA-Z]*f|\brm -[a-zA-Z]*f[a-zA-Z]*r'; then
  if ! echo "$C" | grep -Eq 'rm -[a-zA-Z]+ +(\./)?(node_modules|dist|build|target|\.cache|tmp|/tmp)'; then
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:"recursive delete outside build/cache paths"}}'
    exit 0
  fi
fi

exit 0
