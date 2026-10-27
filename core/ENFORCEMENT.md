# Enforcement by tool

The process is the same everywhere: the files in `docs/pipeline/` and `docs/features/<slug>/`. What differs is how much of it the tool enforces rather than asks.

Three classes of control, and this document names which class each row is:

| Class | Meaning | Here |
|---|---|---|
| instruction | the model is told; it usually complies, and it can do otherwise | scope rules, grounding, fresh-context discipline where the tool has no subagents |
| guardrail | a local mechanism denies the common paths; a process with shell access on the same machine can get around it | the PreToolUse hooks (`guard-git.sh`, `guard-paths.sh`), the `SubagentStop` evidence gate, the git `pre-commit`, `SDLC_ROLE` and `SDLC_HUMAN` switches |
| authoritative | a system outside the agent's reach decides whether the change advances | server-side branch protection and required approvals; CI running `check-feature.sh`, which binds the reports to the exact tree and, with `--run`, executes the repo's own commands |

In the matrix, "enforced" means a guardrail is in place; "rule" means instruction only. `SDLC_HUMAN=1` and `SDLC_ROLE=test-writer` are switches an agent with a shell can set, so they sort out accidents and mark intent; they are not identity. The agent's own reports (the `## Evidence` sections, exit codes, `VERDICT`, `QA`) are testimony the gates check for shape and binding; the authoritative check is CI running the commands on the tree it is about to merge. Checked against each tool's docs on 2026-09-29 (sources in `docs/start/<tool>.md`).

Exercised on real features: Claude Code, Codex CLI, Copilot CLI and VS Code. Checked against documentation only: Gemini CLI and the Copilot cloud agent; a row in those columns says what the docs describe, and a report from a real run is welcome. The git-level checks and CI are tool-independent and are covered by the pipeline repo's own self-test.

| Control | Claude Code | Codex CLI | Copilot CLI / VS Code | Copilot cloud agent | Gemini CLI | Any chat tool |
|---|---|---|---|---|---|---|
| Agents cannot `git commit` / `push` / open MRs (`commit_mode: human`); inline aliases, `--no-verify`, `core.hooksPath`, and `git config` changes to those are denied too | enforced (PreToolUse hook) | enforced (`.codex/hooks.json`, same script) | enforced (`.claude/settings.json` hooks loaded by Copilot) | enforced (`.github/hooks/sdlc.json`); the cloud agent commits to its own PR branch by design, so use it for review only | enforced (`BeforeTool` hook via `gemini-bridge.sh`) | rule + git `pre-commit` |
| Implementer cannot edit tests or CI/lint config, through the edit tools or through the shell (`rm`, `mv`, `sed -i`, redirection, `git rm`/`checkout`/`restore`) | enforced, per subagent; the shell part session-wide | enforced session-wide on `apply_patch`; per-role via `SDLC_ROLE` | enforced session-wide; per-role via agent-frontmatter hooks in VS Code, `SDLC_ROLE` on the CLI | enforced session-wide | enforced session-wide; per-role via `SDLC_ROLE` | rule + `pre-commit` (frozen while a feature is in `implement`) |
| Test-writer edits tests only; doc roles edit `docs/` only | enforced, per subagent | `SDLC_ROLE` per process, else rule | VS Code: agent hooks; CLI: `SDLC_ROLE`, else rule | rule | `SDLC_ROLE`, else rule | rule |
| Reviewer cannot read `fix-notes.md` | enforced (Read hook on the subagent) | rule (Read is not a hookable tool) + fresh subagent | rule + fresh subagent | rule + fresh run | rule + fresh subagent | rule + new conversation |
| Reviewer starts with no implementer history | enforced (subagent) | enforced (`spawn_agent`) | enforced (subagent has its own context window) | enforced (new run) | enforced (subagent) | you open a new conversation |
| Report must carry Evidence, test command, exit codes, VERDICT | enforced (SubagentStop blocks twice) | enforced (SubagentStop) | enforced (`subagentStop` with `decision: block`) | `subagentStop` hook | `check-evidence.sh` by hand or CI (AfterAgent covers the main agent only) | `check-evidence.sh` |
| `security_cmd` runs and exits 0 (when configured) | enforced (SubagentStop requires it in implementer and reviewer reports) + CI `--run` | enforced (SubagentStop) | enforced (`subagentStop`) | `subagentStop` hook | `check-evidence.sh` + CI | `check-evidence.sh` + CI |
| Staged secrets (gitleaks, when installed) | `pre-commit` | `pre-commit` | `pre-commit` | server-side secret scanning | `pre-commit` | `pre-commit` |
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

- `pre-commit`: `ln -sf ../../docs/pipeline/enforcement/pre-commit .git/hooks/pre-commit`. Fails closed when `jq` is missing (`SDLC_SKIP_PRECOMMIT=1` for one commit). Runs `gitleaks protect --staged` when `gitleaks` is on PATH and denies on a finding (`SDLC_SKIP_SECRETS=1` once); prints a notice and continues when it is not installed, since a missing optional scanner is a gap to report, not a reason to block every commit. Denies a commit on a protected branch; denies any commit unless `SDLC_HUMAN=1` is set (set it per command, `SDLC_HUMAN=1 git commit ...`, or in a git alias; never export it globally where an agent launched from your shell inherits it); denies staged edits to `test_globs` or `protected_config_globs` while any feature is at stage `implement` unless `SDLC_ROLE=test-writer` (tests) or `SDLC_ALLOW_CONFIG=1`.
- `tree-hash.sh`: prints a content hash of the working tree (tracked and untracked, `.gitignore` respected) excluding `docs/features/` and the pipeline logs. Review and QA paste it as a `Tree:` line; the same content gives the same hash after the human commits, so CI can tell whether what it checks is what was reviewed.
- `check-evidence.sh <file>`: fails if a report lacks `## Evidence`, the repo's `test_cmd` verbatim, an exit code, a `VERDICT:` or `QA:` line where applicable, and a `Tree:` line in review and QA reports.
- `check-feature.sh <slug> [--run]`: fails unless `state.json.spec_sha` equals `git hash-object docs/features/<slug>/spec.md`, every entry in `state.json.manifest` (ticket, prd, spec, data-model, pipeline.json, written at handoff) still matches its file, the last `VERDICT:` is `APPROVE`, `qa-report.md` says `QA: PASS`, the `Tree:` recorded by review and by QA equals the tree being checked, no task is unchecked, and both reports pass `check-evidence.sh`. With `--run` it also executes `test_cmd`, `lint_cmd`, `typecheck_cmd`, and `security_cmd` from `pipeline.json` and fails on a non-zero exit; that is the authoritative check and belongs in a CI job that has the repo's toolchain. `ci/` has the GitLab include and the GitHub workflow; both read `Feature: <slug>` from the MR description (the `pr-body.md` template carries that line).
