#!/usr/bin/env bash
# PreToolUse hook on Read, attached to code-reviewer. Denies reading the implementer's fix notes
# so the reviewer verifies from code and test output only.
set -u
INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
case "$FILE" in
  *fix-notes.md)
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"reviewer isolation: fix-notes.md is the implementer'"'"'s narrative. Verify each finding from the code and by running tests."}}'
    ;;
esac
exit 0
