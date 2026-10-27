# Other tools (Grok, Cursor, a web chat, anything with repo access)

The process is files; any assistant that can read the repo can run it. What you lose is enforcement, and you replace it with habits and the git checks.

## Give it the instructions

Paste `AGENTS.md` as the system prompt or first message (Cursor and several others read `AGENTS.md` on their own; check the tool). It carries the stage and role tables and five always-on rules, and points at `docs/pipeline/rules/` and `docs/pipeline/stages/` for the full text; paste the relevant rule or stage file when the tool reaches it.

## Run a stage

Say: "Open `docs/pipeline/stages/prd.md` and follow it for slug `my-feature`." The playbooks are written with `{slug}` placeholders and are readable by a person.

## Run a role

Open a **new conversation**, paste `docs/pipeline/roles/<role>.md`, then the slug and only the inputs the playbook lists. The reviewer must never see the implementer's conversation or `fix-notes.md`. `docs/pipeline/RUNNING-ROLES.md` has the rules.

## Enforcement you still have

- `ln -sf ../../docs/pipeline/enforcement/pre-commit .git/hooks/pre-commit`: denies commits on protected branches, denies any commit without `SDLC_HUMAN=1`, freezes tests and config while a feature is in `implement`.
- `docs/pipeline/enforcement/check-evidence.sh <report>` after every role run.
- `check-feature.sh <slug>` in CI (GitLab and GitHub snippets in `docs/pipeline/enforcement/ci/`).

Grok: as of the check on 2026-09-29 there was no agentic Grok CLI with a documented instructions-file convention to verify; treat it as a chat tool and use this page.
