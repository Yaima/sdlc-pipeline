# QA: {slug}

Preconditions: `review-log.md` latest round is `VERDICT: APPROVE`; `state.json.stage` is `review`.

1. Run the gate check in `docs/pipeline/rules/roles.md` for the `qa` gate. Set `state.json.stage: "qa"`. Run role `qa-engineer` with slug `{slug}`. Before it runs, list untracked files (`git ls-files --others --exclude-standard`) and flag anything that is not source, test, docs, or migration (build binaries, junit/coverage output, IDE files) as a `.gitignore` follow-up in `tasks.md`.
2. `QA: PASS`: in `commit_mode: agent`, rebase the feature branch on `base_branch` if behind (stop on conflicts and report) and open the PR/MR per `docs/pipeline/rules/git.md`. In `commit_mode: human` (default), write the PR body to `docs/features/{slug}/pr-body.md` from the template and stop. Set `state.json.stage: "pr"`. Reply with the PR/MR URL or the body path, and the line "Commit and merge are yours."
3. `QA: FAIL`: show the failed rows. For each defect of severity blocker or major, ask the user: fix now (runs `/review {slug}` after the implementer fixes it, since a change invalidates the approval) or record as a follow-up in `tasks.md`. Do what they say.
4. `QA: BLOCKED` or `QA: NOT READY`: show the reason and stop.
