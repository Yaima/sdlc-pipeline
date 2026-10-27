# Enforcement by tool

The process is the same everywhere: the files in `docs/pipeline/` and `docs/features/<slug>/`. What differs is how much of it the tool enforces rather than asks. "Enforced" means the agent cannot do otherwise; "rule" means it is told and usually complies. Checked against each tool's docs on 2026-09-29 (sources in `docs/start/<tool>.md`).

Exercised on real features: Claude Code, Codex CLI, Copilot CLI and VS Code. Checked against documentation only: Gemini CLI and the Copilot cloud agent; a row in those columns says what the docs describe, and a report from a real run is welcome. The git-level checks and CI are tool-independent and are covered by the pipeline repo's own self-test.

| Control | Claude Code | Codex CLI | Copilot CLI / VS Code | Copilot cloud agent | Gemini CLI | Any chat tool |
|---|---|---|---|---|---|---|
| Agents cannot `git commit` / `push` / open MRs (`commit_mode: human`) | enforced (PreToolUse hook) | enforced (`.codex/hooks.json`, same script) | enforced (`.claude/settings.json` hooks loaded by Copilot) | enforced (`.github/hooks/sdlc.json`); the cloud agent commits to its own PR branch by design, so use it for review only | enforced (`BeforeTool` hook via `gemini-bridge.sh`) | rule + git `pre-commit` |
| Implementer cannot edit tests or CI/lint config | enforced, per subagent | enforced session-wide on `apply_patch`; per-role via `SDLC_ROLE` | enforced session-wide; per-role via agent-frontmatter hooks in VS Code, `SDLC_ROLE` on the CLI | enforced session-wide | enforced session-wide; per-role via `SDLC_ROLE` | rule + `pre-commit` (frozen while a feature is in `implement`) |
| Test-writer edits tests only; doc roles edit `docs/` only | enforced, per subagent | `SDLC_ROLE` per process, else rule | VS Code: agent hooks; CLI: `SDLC_ROLE`, else rule | rule | `SDLC_ROLE`, else rule | rule |
| Reviewer cannot read `fix-notes.md` | enforced (Read hook on the subagent) | rule (Read is not a hookable tool) + fresh subagent | rule + fresh subagent | rule + fresh run | rule + fresh subagent | rule + new conversation |
| Reviewer starts with no implementer history | enforced (subagent) | enforced (`spawn_agent`) | enforced (subagent has its own context window) | enforced (new run) | enforced (subagent) | you open a new conversation |
| Report must carry Evidence, test command, exit codes, VERDICT | enforced (SubagentStop blocks twice) | enforced (SubagentStop) | enforced (`subagentStop` with `decision: block`) | `subagentStop` hook | `check-evidence.sh` by hand or CI (AfterAgent covers the main agent only) | `check-evidence.sh` |
| Spec pinned; stale spec blocks implement and review | rule + CI | rule + CI | rule + CI | rule + CI | rule + CI | rule + CI |
| MR needs `VERDICT: APPROVE` and `QA: PASS` | CI `check-feature.sh` | CI | CI | CI | CI | CI |
| Protected branches read-only for agents | enforced + server branch protection | enforced | enforced | server branch protection | enforced | `pre-commit` + server |

`install.sh --guards-only` installs this table's controls without the process: the hooks, the git pre-commit, `check-evidence.sh`, `check-feature.sh`, the CI snippets, and `pipeline.json`. In that mode there are no per-role subagents, so the path guard runs on every edit in the implementer's mode (tests and protected config read-only) and `SDLC_ROLE` selects another mode per process.

Three things follow:

1. Put `check-feature.sh` in CI on every repo. It is the one control identical for every tool and every teammate.
2. Outside Claude Code and VS Code, role scoping is one session-wide hook. The default mode is the implementer's (tests and config read-only), which is the safe direction: a test-writer step needs `SDLC_ROLE=test-writer` in that process's environment, or a person edits the tests.
3. With a plain chat tool, the reviewer's fresh context is something you provide by opening a new conversation. No git hook replaces it.

## `SDLC_ROLE`

`guard-paths.sh` reads `SDLC_ROLE` and picks the edit mode from it: `test-writer` → tests only; `code-reviewer`, `requirements-analyst`, `architect`, `product-manager`, `estimator`, `retro` → `docs/` only; `implementer` or unset → tests and config read-only. Claude Code ignores it (each subagent carries its own mode). For the others, set it per process: `SDLC_ROLE=test-writer codex exec ...`.

## The git-level checks (all tools)

`docs/pipeline/enforcement/`:

- `pre-commit`: `ln -sf ../../docs/pipeline/enforcement/pre-commit .git/hooks/pre-commit`. Denies a commit on a protected branch; denies any commit unless `SDLC_HUMAN=1` is set (set it per command, `SDLC_HUMAN=1 git commit ...`, or in a git alias; never export it globally where an agent launched from your shell inherits it); denies staged edits to `test_globs` or `protected_config_globs` while any feature is at stage `implement` unless `SDLC_ROLE=test-writer` (tests) or `SDLC_ALLOW_CONFIG=1`.
- `check-evidence.sh <file>`: fails if a report lacks `## Evidence`, the repo's `test_cmd` verbatim, an exit code, and a `VERDICT:` or `QA:` line where applicable.
- `check-feature.sh <slug>`: fails unless `state.json.spec_sha` equals `git hash-object docs/features/<slug>/spec.md`, the last `VERDICT:` is `APPROVE`, `qa-report.md` says `QA: PASS`, no task is unchecked, and both reports pass `check-evidence.sh`. `ci/` has the GitLab include and the GitHub workflow; both read `Feature: <slug>` from the MR description (the `pr-body.md` template carries that line).
