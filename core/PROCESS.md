# Pipeline process (contract between stages)

Each stage reads specific files, writes specific files, and updates `docs/features/<slug>/state.json`. A stage refuses to start if its inputs are missing or the state says an earlier stage is incomplete.

## Feature folder

```
docs/features/<slug>/
  state.json       stage, review_round, verdicts, timestamps
  ticket.md        the request verbatim; the scope authority (rules/scope.md)
  prd.md           requirements R1..Rn with a source each, acceptance criteria, out of scope
  spec.md          technical design, R-id → component map, risks
  data-model.md    entities, relations, migrations (only when data model changes)
  tasks.md         ordered task list; each task names its R-ids and test files
  review-log.md    one section per review round: verdict, coverage, findings
  fix-notes.md     implementer's per-round narrative; reviewer never reads it
  qa-report.md     acceptance test results per R-id
```

Stages: grill → prd → handoff → implement → review → qa → pr. That is the `full` tier; `stages/feature.md` sizes a feature into `lite` (starts at a one-paragraph spec), `standard` (starts at prd), or `full` from the requirements-analyst's blast radius and sizes, and records the tier in `state.json.mode`. `estimate` is optional and sits outside the sequence: run it any time after `ticket.md` exists; it writes `estimate.md` and changes no stage. Extra states: `needs-human` (cap hit, BLOCKED, or test dispute) and `awaiting-<gate>` (handed to another role).

## Stage gates

| Stage | Requires | Produces | Gate to next |
|---|---|---|---|
| prd | an idea from the user | prd.md | user confirms the requirement list |
| handoff | prd.md | spec.md, data-model.md?, tasks.md | requirements-analyst finds no unresolved conflicts with the codebase; user confirms the task list |
| implement | tasks.md, spec.md | code + tests, all tasks checked off | `test_cmd` exits 0 |
| review | a diff against the base branch | review-log.md round N | VERDICT: APPROVE |
| fix | review-log.md with CHANGES_REQUESTED | code changes, tests rerun | round < max_review_rounds |
| qa | APPROVE in review-log.md | qa-report.md | all R-ids pass |
| pr | qa-report.md all pass | a pull request with the review-log and qa-report linked | human merge |

## state.json

See `templates/state.json` for the full field list: stage, mode (lite/standard/full, see `stages/feature.md`), review_round, last_verdict, last_reviewed_files, blast_radius, spec_sha, data_model_sha, waived_findings, handoffs, cost_usd, history.

Agents update `stage` and append to `history` when they finish, with `at` taken from `date -u +%Y-%m-%dT%H:%M:%SZ` (never typed by hand). They never skip a stage by editing `state.json` directly. `related[]` lists sibling repos, shared contracts, and upstream docs; see `rules/grounding.md`.

## Review verdicts

The reviewer's first line is one of:

- `VERDICT: APPROVE` — no blocker or major findings, tests pass, every R-id has a test.
- `VERDICT: CHANGES_REQUESTED` — at least one blocker or major finding. Implementer fixes only those. Minors and nits go to `tasks.md` under "Follow-ups".
- `VERDICT: BLOCKED` — the reviewer cannot proceed (tests will not run, spec contradicts PRD, diff is missing). The orchestrator stops and reports to the user.

## Loop termination

The fix loop ends when the verdict is APPROVE, or when `review_round == max_review_rounds`. On cap, the orchestrator writes the open findings to the top of `review-log.md` under "Needs human decision" and stops.

## Who may do what (enforced; see docs/pipeline/ENFORCEMENT.md)

| Agent | May edit | Denied |
|---|---|---|
| test-writer | files matching `test_globs`, docs/ | everything else |
| implementer | source files | `test_globs`, `protected_config_globs` |
| code-reviewer | `docs/` only | source, tests; reading `fix-notes.md` |
| product-manager, requirements-analyst, architect, estimator, retro | `docs/` only | everything else |
| qa-engineer | acceptance tests, `docs/` | (advisory) |
| humans | merge | agents: push to protected branches, `gh pr merge` |

Only `code-reviewer` writes a VERDICT line. Only humans merge. With `commit_mode: human` (default) only humans commit and push; agents leave changes in the working tree, and the pipeline denies `git commit`, `git push`, rebase, and PR/MR creation.

## Proof of work (enforced; see docs/pipeline/ENFORCEMENT.md)

The stop check (Claude Code: SubagentStop hook; other tools: `check-evidence.sh`, see ENFORCEMENT.md) blocks implementer, test-writer, code-reviewer, and qa-engineer from finishing until their report contains an `## Evidence` section, the repo's test command, and exit codes (plus a VERDICT or QA line where applicable). It blocks at most twice per run, then lets the agent finish and marks the report unverified on stderr.

## Reviewer isolation

The reviewer receives the diff, the docs, and prior finding ids. It never receives the implementer's fix notes (`fix-notes.md`, read-denied by the tool's enforcement (ENFORCEMENT.md)) or any summary of what was done. It re-verifies each prior finding from code and test output. Rounds after the first review the diff since `state.json.last_reviewed_files` plus the full files that diff touches.

## Blast radius and second review

The requirements-analyst sets `state.json.blast_radius` (low / medium / high). When it matches `second_review_on_blast_radius` in `pipeline.json`, round 1 gets a second, separate review pass (`/code-review` plugin (Claude Code), or a second reviewer run on a different model). Findings from both passes are merged; disagreements are listed, not resolved by the orchestrator.

## Spec pinning and task size

`/handoff` records `spec_sha`, `data_model_sha`, and `state.json.manifest` (hashes of ticket, prd, spec, data-model, and pipeline.json). Implementer and reviewer stop with BLOCKED if the spec changed since; CI (`check-feature.sh`) fails if any manifest entry changed after handoff, if the `Tree:` hash recorded by review or QA differs from the tree under check, and, with `--run`, if the repo's own commands fail on that tree. Tasks are capped by `max_task_loc` (default 300); the architect splits larger ones.

## Operator roles

Human gates have owner roles (`docs/pipeline/rules/roles.md`). A stage skill run by someone who does not own the gate records a handoff in `state.json.handoffs[]` and stops. `/start` shows each person what is waiting on them.
