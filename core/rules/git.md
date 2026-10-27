# Git rules

- Work on the branch named in `state.json.feature_branch` (default `feat/<slug>`), branched from `base_branch` in `docs/pipeline/pipeline.json`. Create it if missing; keep it if the user created it (ticket branches).
- `commit_mode` in `docs/pipeline/pipeline.json` decides who commits. `human` (default): agents never run `git commit`, `git push`, `git add -A`, rebase, or open PRs/MRs; they leave changes in the working tree and end their report with the list of changed files (`git status --short`). These commands are denied (see docs/pipeline/ENFORCEMENT.md). `agent`: commit after each task in `tasks.md` passes, as `<type>(<slug>): <summary>` with a `Refs: R1, R2` body line, prefixed with `state.json.ticket` when set.
- Task completion is tracked by the checkbox in `tasks.md` and the test run in the report, never by a commit.
- In `agent` mode, push feature branches only. Protected branches are read-only for agents (enforced; see docs/pipeline/ENFORCEMENT.md).
- In `agent` mode, open a PR/MR once QA passes with the tool named in `pipeline.json.pr_tool`; in `human` mode, write the PR body to `docs/features/<slug>/pr-body.md` and stop: `gh pr create` (GitHub) or `glab mr create` (GitLab). PR body: link to `prd.md`, `spec.md`, the final `review-log.md` verdict, and `qa-report.md`. Include a checklist of R-ids.
- Never run `gh pr merge`, `glab mr merge`, `glab mr approve`, force push, `reset --hard`, or branch deletion. These are human actions.
- In `agent` mode, rebase onto base before opening the PR if the branch is behind; stop and report on conflicts. In `human` mode, report `git rev-list --count HEAD..<base>` and stop.
