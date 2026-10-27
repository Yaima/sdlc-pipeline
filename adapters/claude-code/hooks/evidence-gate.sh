#!/usr/bin/env bash
# SubagentStop hook. Refuses to let pipeline agents finish without proof of work.
# Checks last_assistant_message for:
#   - an "## Evidence" section (all pipeline agents)
#   - the repo's test command and an exit code (implementer, test-writer, code-reviewer, qa-engineer)
#   - a VERDICT line (code-reviewer) / QA: line (qa-engineer)
# Blocks at most twice per agent run (marker file), then lets it finish with a warning so runs cannot loop forever.
set -u
INPUT=$(cat)
MSG=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // ""')
AGENT=$(printf '%s' "$INPUT" | jq -r '.agent_type // .agent_name // .subagent_type // .agent // ""')
if [ -z "$AGENT" ]; then
  tp=$(printf '%s' "$INPUT" | jq -r '.agent_transcript_path // .transcript_path // empty')
  [ -f "$tp" ] && AGENT=$(head -c 4000 "$tp" | grep -oE '"(agent_type|subagent_type|agentType)":"[^"]+"' | head -1 | cut -d'"' -f4)
fi
# Unknown agent: still require an Evidence section if the message looks like a pipeline report
if [ -z "$AGENT" ] && printf '%s' "$MSG" | grep -Eq '^(VERDICT|QA):|tasks\.md|review-log\.md'; then AGENT="unknown-pipeline"; fi
AID=$(printf '%s' "$INPUT" | jq -r '.agent_id // .session_id // "na"')
ROOT="${CLAUDE_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"
CFG="$ROOT/docs/pipeline/pipeline.json"; [ -f "$CFG" ] || CFG="$ROOT/.claude/pipeline.json"

case "$AGENT" in
  implementer|test-writer|code-reviewer|qa-engineer|requirements-analyst|architect|product-manager|retro|unknown-pipeline) ;;
  *) exit 0 ;;
esac

MARK="${TMPDIR:-/tmp}/evidence-gate-${AID}.count"
n=0; [ -f "$MARK" ] && n=$(cat "$MARK")
if [ "$n" -ge 2 ]; then
  echo "evidence-gate: $AGENT finished after $n blocks without full evidence; treat its report as unverified." >&2
  rm -f "$MARK"; exit 0
fi

missing=()
printf '%s' "$MSG" | grep -q '## Evidence' || missing+=("an '## Evidence' section listing files read (path:line), commands run with exit codes, and things looked for and not found")

case "$AGENT" in
  implementer|test-writer|code-reviewer|qa-engineer)
    TEST_CMD=""; [ -f "$CFG" ] && TEST_CMD=$(jq -r '.test_cmd // ""' "$CFG")
    if [ -n "$TEST_CMD" ]; then
      printf '%s' "$MSG" | grep -Fq "$TEST_CMD" || missing+=("the test command from docs/pipeline/pipeline.json ($TEST_CMD) as actually run, verbatim")
    fi
    printf '%s' "$MSG" | grep -Eiq 'exit (code|status)[: ]+[0-9]+|rc=[0-9]+' || missing+=("the exit code of each command run (write 'exit code N')")
    ;;
esac
case "$AGENT" in
  code-reviewer) printf '%s' "$MSG" | grep -Eq '^VERDICT: (APPROVE|CHANGES_REQUESTED|BLOCKED)' || missing+=("a first line 'VERDICT: APPROVE|CHANGES_REQUESTED|BLOCKED'") ;;
  qa-engineer)   printf '%s' "$MSG" | grep -Eq '^QA: (PASS|FAIL|BLOCKED|NOT READY)' || missing+=("a first line 'QA: PASS|FAIL|BLOCKED|NOT READY'") ;;
  test-writer)   printf '%s' "$MSG" | grep -Eiq '(^|[^a-z])fail' || missing+=("the failure output of the new tests (they must fail before implementation)") ;;
esac

if [ "${#missing[@]}" -gt 0 ]; then
  echo $((n+1)) > "$MARK"
  reason="Your report is incomplete. Add: $(printf '%s; ' "${missing[@]}")Run the commands if you have not; paste real output, never a summary."
  jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"SubagentStop",decision:"block",reason:$r}}'
  exit 0
fi
rm -f "$MARK"
exit 0
