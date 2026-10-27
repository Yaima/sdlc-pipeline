#!/usr/bin/env bash
# Gemini CLI BeforeTool hook -> the Claude-style guard scripts.
# Usage in .gemini/settings.json: "command": ".claude/hooks/gemini-bridge.sh guard-git"  (or guard-paths <mode>)
# Gemini sends {"tool_name": "run_shell_command"|"write_file"|"replace"|..., "tool_input": {...}} and expects
# {"decision": "deny", "reason": "..."} on stdout (exit 0), or exit 2 with the reason on stderr.
set -u
GUARD="${1:?guard name}"; shift || true
HERE="$(cd "$(dirname "$0")" && pwd)"
INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')
case "$TOOL" in
  run_shell_command) MAPPED=$(printf '%s' "$INPUT" | jq '{tool_name:"Bash", tool_input:{command:(.tool_input.command // "")}}') ;;
  write_file|replace|edit|create_file) MAPPED=$(printf '%s' "$INPUT" | jq '{tool_name:"Write", tool_input:{file_path:(.tool_input.file_path // .tool_input.path // "")}}') ;;
  read_file) MAPPED=$(printf '%s' "$INPUT" | jq '{tool_name:"Read", tool_input:{file_path:(.tool_input.file_path // .tool_input.path // "")}}') ;;
  *) exit 0 ;;
esac
OUT=$(printf '%s' "$MAPPED" | "$HERE/$GUARD.sh" "$@" 2>/tmp/sdlc-bridge-err.$$); CODE=$?
ERR=$(cat /tmp/sdlc-bridge-err.$$ 2>/dev/null); rm -f /tmp/sdlc-bridge-err.$$
if [ $CODE -eq 2 ]; then
  jq -n --arg r "${ERR:-denied by pipeline guard}" '{decision:"deny", reason:$r}'; exit 0
fi
DEC=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)
if [ "$DEC" = "deny" ]; then
  printf '%s' "$OUT" | jq '{decision:"deny", reason:(.hookSpecificOutput.permissionDecisionReason // "denied by pipeline guard")}'
fi
exit 0
