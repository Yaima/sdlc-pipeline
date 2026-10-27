# Review: {slug}

Preconditions: `state.json.stage` is `implement` or `review`, all tasks in `tasks.md` are checked, the working tree differs from `base_branch` (`git diff <base_branch> --stat` or untracked files). Read `max_review_rounds`, `second_review_on_blast_radius`, and `second_review_method` from `docs/pipeline/pipeline.json`; copy `max_review_rounds` into `state.json` if absent. Run the gate check in `docs/pipeline/rules/roles.md` for the `review` gate.

Set `state.json.stage: "review"`.

## Loop

Repeat:

1. Increment `state.json.review_round`. Run role `code-reviewer` with slug `{slug}`, the round number, and (rounds after the first) the open finding ids with their text from the previous round. Pass nothing else. Never pass `fix-notes.md` or any summary of what the implementer did.
2. **Second pass**, only on round 1 and only if `state.json.blast_radius` is listed in `second_review_on_blast_radius`:
   - `code-review-plugin`: run the bundled `/code-review` skill if the tool has it (Claude Code plugin; it reviews in a forked context). If it is absent, fall back to the next method.
   - `second-agent`: run role `code-reviewer` a second time on a different model where the tool allows choosing one and the instruction "review as a security and data-integrity specialist; ignore style".
   Record the second pass's findings in `review-log.md` with ids `RN-S1`, `RN-S2`, ... exactly as reported. Then run role `code-reviewer` once more with only those ids and the instruction: "rate each per review-standards.md (severity, confidence, reproduction), verify from code, and re-issue the round's VERDICT counting both sets". The re-issued verdict is the round's verdict. List disagreements between the passes; do not resolve them yourself.
3. Read the `VERDICT` line and record it in `state.json.last_verdict`. Record in `state.json.last_reviewed_files` a map of each reviewed file to its `git hash-object` (works for uncommitted files).
4. `APPROVE`: tell the user the round number and finding counts. Update `state.json`, append history, say `/qa {slug}` is next. Stop.
5. `BLOCKED`: show the reviewer's reason to the user and stop. Do not retry.
6. `CHANGES_REQUESTED`:
   - If `review_round >= max_review_rounds`: copy the open blocker/major findings to the top of `review-log.md` under `## Needs human decision`, set `state.json.stage: "needs-human"`, tell the user, and stop. If the user later waives findings, record them under `state.json.waived_findings` with the reason so the true round count and waivers stay visible. Each waived or cap-stopping blocker/major also goes to `docs/pipeline/RULE-CANDIDATES.md` (see "Rule candidates" below).
   - Otherwise: if any open finding says a test is missing, run role `test-writer` first with those finding ids. Then run role `implementer` in fix mode with slug `{slug}`, round number, and the open finding ids with text. If the implementer replies `BLOCKED:`, set `state.json.stage: "needs-human"`, show the reason, and stop. Otherwise loop.

Tell the user one line per round: round number, verdict, counts by severity, and the reviewer's stopping criterion for the next round.

## Rule candidates

A finding a human had to decide is a lesson the agents will otherwise repeat. Whenever this stage stops for a human (round cap, `BLOCKED`, implementer `BLOCKED:`) or a finding is waived, append one line to `docs/pipeline/RULE-CANDIDATES.md` (create it with a `# Rule candidates` heading if missing):

```
- <date> <slug> <finding id or BLOCKED>: <one line: what happened> → candidate: <rule file or CODEBASE.md> "<proposed sentence>"
```

Append only; never edit `docs/pipeline/rules/` from this stage. `retro` reads the file and proposes which candidates become rules; the human applies them and deletes the lines.

## Never

- Never let the implementer and reviewer share a context. One role run each, always fresh.
- Never edit `review-log.md` verdicts yourself.
- Never lower `max_review_rounds` mid-loop or raise it without the user saying so.
- Never forward the implementer's fix notes or claims to the reviewer.
