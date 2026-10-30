#!/usr/bin/env bash
# SubagentStart and SubagentStop hook. Appends one line per event to docs/pipeline/agent-runs.log:
#   <utc> event=start|stop agent=<role> agent_id=<id> session=<id> keys=...
# retro reads it for turn counts; the board in the pipeline checkout pairs start and stop lines to show running roles.
# The keys field records the input's top-level keys, so the agent-name field can be confirmed against the running Claude Code version.
set -u
INPUT=$(cat)
ROOT="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"
mkdir -p "$ROOT/docs/pipeline"
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# Claude Code sends agent_type for subagents it names; the other fields cover older and other tools.
# Only a non-empty string counts, so a null or "" falls through to the next field instead of becoming the role.
agent=$(printf '%s' "$INPUT" | jq -r '[.agent_type, .agent_name, .subagent_type, .agent] | map(select(type == "string" and length > 0)) | first // empty')
if [ -z "$agent" ]; then
  # fall back: the subagent transcript names the agent in most versions, under one of these keys, with or without a space after the colon
  tp=$(printf '%s' "$INPUT" | jq -r '.agent_transcript_path // .transcript_path // empty')
  [ -f "$tp" ] && agent=$(head -c 20000 "$tp" | grep -oE '"(agent_type|subagent_type|agentType|subagentType|agent_name|agentName)": *"[^"]+"' | head -1 | sed -E 's/.*": *"([^"]+)"/\1/')
fi
sid=$(printf '%s' "$INPUT" | jq -r '.session_id // ""')
aid=$(printf '%s' "$INPUT" | jq -r '.agent_id // ""')
keys=$(printf '%s' "$INPUT" | jq -r 'keys|join(",")')
ev=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // ""'); case "$ev" in SubagentStart) ev=start ;; *) ev=stop ;; esac
extra=""
if [ -z "$agent" ]; then
  # Unknown role: keep what agent_type held, so the hook can be fixed from the log instead of guessed.
  extra=" raw_agent_type=$(printf '%s' "$INPUT" | jq -c '.agent_type')"
fi
echo "$ts event=$ev agent=${agent:-unknown} agent_id=$aid session=$sid keys=$keys$extra" >> "$ROOT/docs/pipeline/agent-runs.log"
exit 0
