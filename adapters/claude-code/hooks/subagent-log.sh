#!/usr/bin/env bash
# SubagentStop hook. Appends one line per finished subagent to docs/pipeline/agent-runs.log for retros.
# Also records the top-level input keys once, so the agent-name field can be confirmed against the running Claude Code version.
set -u
INPUT=$(cat)
ROOT="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"
mkdir -p "$ROOT/docs/pipeline"
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
agent=$(printf '%s' "$INPUT" | jq -r '.agent_type // .agent_name // .subagent_type // .agent // empty')
if [ -z "$agent" ]; then
  # fall back: first line of the subagent transcript names the agent in most versions
  tp=$(printf '%s' "$INPUT" | jq -r '.agent_transcript_path // .transcript_path // empty')
  [ -f "$tp" ] && agent=$(head -c 4000 "$tp" | grep -oE '"(agent_type|subagent_type|agentType)":"[^"]+"' | head -1 | cut -d'"' -f4)
fi
sid=$(printf '%s' "$INPUT" | jq -r '.session_id // ""')
keys=$(printf '%s' "$INPUT" | jq -r 'keys|join(",")')
echo "$ts agent=${agent:-unknown} session=$sid keys=$keys" >> "$ROOT/docs/pipeline/agent-runs.log"
exit 0
