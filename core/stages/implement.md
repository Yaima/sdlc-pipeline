# Implement: {slug}

Preconditions: `tasks.md` and `spec.md` exist; `state.json.stage` is `handoff` or `implement`; `docs/pipeline/pipeline.json.test_cmd` is set (if empty, stop and ask the user for it). You are on the branch named in `state.json.feature_branch` (check `git branch --show-current`; switch or create if not).

Run the gate check in `docs/pipeline/rules/roles.md` for the `implement` gate. Set `state.json.stage: "implement"`.

## Loop

For each unchecked task in `tasks.md`, in order (or only task {args} if given):

1. If the task is a test task: run role `test-writer` with slug, task id, and its R-ids. Require the failure output in the reply. If the tests did not fail, or failed on import/syntax, send it back once with the output; if still wrong, stop and report.
2. If the task is an implementation task: run role `implementer` in implementation mode with slug and task id. Require: task tests pass, full suite passes, lint and typecheck pass when configured, task checked off, and (agent mode only) commit made; in human mode, the changed-file list.
3. Proof of work: the implementer's reply must contain the test command, its exit code, and the summary line of the test runner. A reply without it is incomplete; ask once for the proof, then stop and report if it is still missing.
4. On a test dispute (implementer wrote to `tasks.md` under "Test disputes") or a reply starting `BLOCKED:`, set `state.json.stage: "needs-human"`, stop, and show the user the dispute or reason. Do not retry the same task.
5. Tell the user in one line which task finished, then continue.

Run role agents one at a time. Each starts with a fresh context; that is intended. Pass them the slug and task id only, never a summary of earlier tasks. They read the files.

## Finish

When every task is checked: run the full suite yourself once and paste the summary line. Update `state.json`, append history. Reply with `git status --short` (human mode) or `git log --oneline base..HEAD` (agent mode) and say `/review {slug}` is next.
