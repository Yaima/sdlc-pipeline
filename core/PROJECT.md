# Project instructions

Read `docs/pipeline/PROCESS.md` before any pipeline work.

## Repo facts

<!-- Rewrite this section from the repo itself before running any stage. Agents treat every line as true. -->
- Stack: <language and version, module/package name, test framework, DB and ORM, queues, API layer>
- Layout: <top-level dirs and what lives in each; entry points>
- DB: <schema, main tables, where migrations live and how they are applied>
- Base branch: <develop|main>. Hosted on <GitLab|GitHub>; PRs/MRs via <glab|gh>, merged by humans
- Tests: <exact command; what must be running locally (DB port, compose file, env vars)>
- Lint: <exact command and version>; <typecheck command>
- Private deps / credentials: <if any>
- Ticket and branch: set per feature in `docs/features/<slug>/state.json`

## How work flows here

- Every feature lives in `docs/features/<slug>/`. Read `state.json` there before touching a feature.
- Stages are playbooks in `docs/pipeline/stages/<stage>.md`, run as `/prd <slug>`, `/handoff <slug>`, `/implement <slug>`, `/review <slug>`, `/qa <slug>`, or `/feature <slug>` for the whole chain (slash commands where the tool has them; otherwise "run stage prd for <slug>").
- Tests come before implementation. See `docs/pipeline/rules/tdd.md`.
- Code review is done by the `code-reviewer` role in a fresh context, never by the agent that wrote the code. Roles are in `docs/pipeline/roles/`.
- Commit, push, and merge are human actions (`commit_mode: human`). Agents leave changes in the working tree and stop.

## Conventions

- Requirement IDs `R<n>` from the PRD appear in spec sections, task titles, test names, and commit bodies.
- Commits: `<type>(<slug>): <summary>` with `Refs: R1, R3` in the body.
- Keep PRD, spec, and tasks in sync: a change to one triggers a note in `review-log.md`.
