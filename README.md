# SDLC Pipeline

A feature pipeline for AI coding agents that works with Claude Code, Codex CLI, GitHub Copilot, Gemini CLI, or any chat tool with repo access. SDLC is Software Development Life Cycle: the pipeline takes a feature from idea to a merge request through PRD, codebase-checked spec, TDD implementation, an independent review loop, and QA, with a person at every gate and a person doing every commit and merge.

It is built for teams shipping production code with tickets, CI, and protected branches, where an agent that adds unrequested behavior or approves its own work costs real review time. `feature <slug>` sizes each change from the code it touches: a low-blast-radius change runs the lite tier (spec paragraph, tests, implement, review, QA), a medium one adds the PRD and handoff stages, a high one runs everything including a second review pass. For a solo side project the enforcement scripts in `core/enforcement/` also work on their own without the rest.

Status, version `2026.10.27`: Claude Code is the primary target and the one with the most runs. Full features have also run end to end with Codex CLI and GitHub Copilot. The Gemini CLI and Copilot cloud agent adapters are checked against those tools' documentation, dated in `docs/start/<tool>.md`, and maintained on report. The tier sizing in `core/stages/feature.md` is new in this version and has fewer runs behind it than the stage-by-stage path; expect to adjust it. Tool formats change often; a start guide older than six months is a reason to re-check its sources before relying on a row in `ENFORCEMENT.md`.

```
idea ─► grill ─► prd ─► handoff ─► implement ─► review ─► qa ─► pr-body.md  (you commit, push, open the MR, merge)
                           │           ▲           │
                           │           └── fix ◄───┘  until APPROVE or the round cap
                           └── spec + tasks checked against the real code
```

That is the `full` tier. `standard` starts at `prd`; `lite` starts at a one-paragraph spec. All three share implement, review, and qa.

## Security checks

Two layers, and the pipeline names which is which. The reviewer applies a checklist to every boundary the diff touches (input validation, authorization on new endpoints or actions, secrets in code, unsafe deserialization, injection, path traversal, unbounded resource use); a security flaw is a blocker, and auth, permissions, payments, migrations, and public API changes get a second review pass. That layer is a model reading code. The deterministic layer is `security_cmd` in `pipeline.json`, run by the implementer and the reviewer, required by the evidence gate, and executed by CI with `check-feature.sh --run`; and the git `pre-commit`, which runs `gitleaks protect --staged` when `gitleaks` is installed and says so when it is not. The pipeline ships no scanner of its own; the repo chooses one.

## Trust boundary

Three classes of control, named as such throughout the docs. **Instructions** are what the role prompts say; the model usually follows them. **Guardrails** are local mechanisms: the hooks that deny `git commit`, test-file edits, and reports without evidence, and the git `pre-commit`. They stop the common paths, and a process with a shell on the same machine can get around them, so they count as accident prevention and intent marking. **Authoritative controls** sit outside the agent's reach: branch protection on the server, and CI running `check-feature.sh`, which checks that the reports exist, binds them to the exact tree under review (`Tree:` hashes and a handoff manifest), and with `--run` executes the repo's own test, lint, and typecheck commands. The agent's reports are testimony; CI running the commands is the check. `core/ENFORCEMENT.md` classifies every control.

## How it is organized

```
core/            the process, tool-neutral. Edit this and nothing else.
  PROCESS.md, ENFORCEMENT.md, RUNNING-ROLES.md, PROJECT.md (instructions template), pipeline.json (config template)
  rules/         always-on rules: grounding, tdd, review-standards, git, roles
  roles/         one prompt per role: product-manager, requirements-analyst, architect,
                 test-writer, implementer, code-reviewer, qa-engineer, estimator, retro
  stages/        one playbook per stage: start, codebase-map, grill, prd, handoff,
                 implement, review, qa, feature, roadmap, retro, estimate (optional)
  templates/     prd, spec, data-model, tasks, review-log, qa-report, pr-body, state.json
  enforcement/   git pre-commit, tree-hash.sh, check-evidence.sh, check-feature.sh, CI snippets
adapters/claude-code/   hook scripts and agent metadata (tools, model, turn caps, guard modes)
docs/start/      per-tool start guides with sources (claude-code, codex, copilot, gemini, other-tools)
docs/research.md the evidence behind the design choices (reviewer bias, test tampering, loop convergence), with sources
tests/run.sh     self-test: builds dist/, installs into scratch repos, runs every hook and check against known inputs
build.py         core/ -> dist/ (generated, gitignored)
install.sh       ./install.sh /path/to/repo [--minimal|--guards-only]
```

`install.sh` writes one tree that all four tools read, because in 2026 they converged on the same files:

| Installed file | Read by |
|---|---|
| `AGENTS.md` (your Repo facts + a generated pipeline block: stage and role tables, five always-on rules, pointers to the rule files) | Codex, Copilot, Gemini (via `.gemini/settings.json`), Claude Code through `CLAUDE.md` = `@AGENTS.md` |
| `.agents/skills/<stage>/SKILL.md` and the same under `.claude/skills/` | Codex, Copilot, Gemini; Claude Code (which does not read `.agents/`) |
| `.claude/agents/<role>.md` | Claude Code, Copilot CLI and VS Code |
| `.codex/agents/<role>.toml`, `.gemini/agents/<role>.md`, `.github/agents/<role>.md` | Codex, Gemini, Copilot cloud agent |
| `.claude/hooks/*.sh` (one set of guard scripts) | every tool below |
| `.claude/settings.json`, `.codex/hooks.json`, `.gemini/settings.json`, `.github/hooks/sdlc.json` | Claude Code + Copilot CLI/VS Code, Codex, Gemini (through `gemini-bridge.sh`), Copilot cloud agent |
| `docs/pipeline/` | people, and every tool when a playbook points at it |

`--minimal` skips `.codex/`, `.gemini/`, `.github/` for a team on Claude Code and Copilot only. Read `core/ENFORCEMENT.md` for what each tool enforces vs. asks, and `docs/start/<tool>.md` before the first run on a tool. The file formats were checked against each tool's official docs on 2026-09-29; the start guides carry the sources.

## Install in a repo

Needs `bash`, `python3`, `jq`, and `git` on PATH; the target is an existing git repository. Install runs from this checkout and copies files into the target; it never writes outside the target.

```bash
git clone https://github.com/Yaima/sdlc-pipeline.git ~/src/sdlc-pipeline
cd ~/src/sdlc-pipeline
./install.sh /path/to/your-repo             # all tools
./install.sh /path/to/your-repo --minimal   # Claude Code + Copilot only
```

### Guards only

```bash
./install.sh /path/to/your-repo --guards-only
```

Installs the enforcement layer and nothing else: the hooks (agents cannot commit, push, or merge; test files and CI/lint config are read-only for them; a pipeline role cannot finish without evidence), `.claude/settings.json` with those hooks and the permission allowlist, the git `pre-commit`, `check-evidence.sh`, `check-feature.sh`, the CI snippets, and `pipeline.json` for the globs and commands. No roles, stages, or changes to your instructions file. Edit `test_globs`, `protected_config_globs`, and `protected_branches` in `pipeline.json` to match the repo. The path guard runs session-wide in this mode; `SDLC_ROLE=test-writer` in a process's environment lets that process edit tests. Running `install.sh` again without the flag adds the full pipeline and keeps `pipeline.json`.

To try it without committing pipeline files to a shared repo, list the installed paths (`AGENTS.md`, `CLAUDE.md`, `.claude/`, `.agents/`, `.codex/`, `.gemini/`, `.github/agents/`, `.github/hooks/`, `docs/pipeline/`, `docs/features/`) in the target's `.git/info/exclude`. Everything works the same; nothing shows in `git status`.

Then, in the target repo:

1. `docs/pipeline/pipeline.json`: `test_cmd`, `lint_cmd`, `typecheck_cmd`, `security_cmd`, `coverage_cmd`, `base_branch`, `pr_tool`. Match the Makefile and CI exactly (timeouts, flags). Leave `""` when the repo has none. `security_cmd` is the repo's own scanner (for example `gosec ./...`, `bandit -r . && pip-audit`, `npm audit --audit-level=high`, `semgrep --config auto`, `gitleaks detect`); the implementer and reviewer run it, the evidence gate requires it, and CI runs it with `--run`. Without one, security review is the reviewer's checklist only, and the review log says so. `install.sh` turns these commands into a `permissions.allow` list in `.claude/settings.json`, so agents run them without a prompt; re-run `install.sh` after changing them. Your own extra permissions go in `.claude/settings.local.json` (gitignored), which install never touches.
2. `docs/pipeline/pipeline.local.json`: your name and role (`solo`, `product`, `engineer`, `qa`, `reviewer`). Gitignored; each teammate has their own.
3. `AGENTS.md`: rewrite **Repo facts** from the repo itself (the pipeline block below it is generated; leave it). Every agent reads it first and treats every line as true. A copied or guessed line (wrong test framework, a function that does not exist) costs a full handoff round.
4. `ln -sf ../../docs/pipeline/enforcement/pre-commit .git/hooks/pre-commit`, and `export SDLC_HUMAN=1` only in the shell where you commit (not globally, or agents inherit it).
5. Add the CI check: `docs/pipeline/enforcement/ci/gitlab-ci.sdlc.yml` (include) or `github-sdlc-check.yml` (copy to `.github/workflows/`). It fails a merge request whose feature lacks `VERDICT: APPROVE`, `QA: PASS`, a pinned spec and manifest, evidence, or whose reviewed `Tree:` hash differs from the tree being merged. Add `--run` in a job that has the repo's toolchain so CI also executes `test_cmd`, `lint_cmd`, and `typecheck_cmd`; that is the authoritative check. Turn on branch protection with the check required.
6. Open the repo in your tool and accept its workspace-trust prompt (hooks run only in a trusted workspace). Run `/codebase-map`, read `docs/pipeline/CODEBASE.md`, and correct it; agents read it before every run. Create the ticket branch from `base_branch`. Run `/start`.

Stages are slash commands in Claude Code, Codex, Copilot, and Gemini (`/feature`, `/review`, ...). In a tool without slash commands, say "run stage feature for <slug>" and paste `docs/pipeline/stages/feature.md`; `docs/start/other-tools.md` covers that case.

## First feature, start to finish

What a first run looks like with Claude Code, role `solo`, on a repo where `pipeline.json` has a real `test_cmd`:

1. `git checkout -b feat/rate-limit` from `base_branch`. `claude`. The SessionStart hook prints your role and "no features in progress".
2. `/feature rate-limit limit login attempts to 5 per minute per account`. The skill writes `docs/features/rate-limit/ticket.md` with your sentence verbatim, drafts R1 from it, runs the requirements-analyst (it reads the auth code and reports blast radius with the paths), and asks you to confirm a tier. Answer `lite`, `standard`, or `full`, or accept the proposal.
3. Each gate is a question in the session; your answer is recorded verbatim in `decisions.md`. Typical gates: confirm the R-ids, answer `[ADDS SCOPE]` questions (each one is behavior the ticket did not ask for; "no" is a complete answer), confirm the task list.
4. `implement` runs test-writer then implementer per task and prints one line per task. `review` prints one line per round: verdict and counts. The session stops on `needs-human` with the reason.
5. After `QA: PASS` the skill writes `docs/features/rate-limit/pr-body.md` and says "Commit and merge are yours." `git status --short`, then `SDLC_HUMAN=1 git commit`, push, open the MR from `pr-body.md`.
6. Later: `/retro rate-limit`, apply the rule edits you agree with.

To resume after closing the session: `claude`, then `/start`; it lists features by stage and the command that continues each.

Re-running `install.sh` updates the generic files, replaces the generated block in `AGENTS.md`, and leaves your Repo facts, `pipeline.json`, `CODEBASE.md`, and `docs/features/` alone. `docs/pipeline/VERSION` says what a repo has. A repo on the older layout (`.claude/pipeline.json`, `.claude/rules/`, a full `CLAUDE.md`) is migrated in place: Repo facts move into `AGENTS.md`.

## Run a feature

One session per repo. For a feature that spans two repos, run the pipeline in each and list the sibling in `state.json.related[]`.

`feature <slug> <idea>` is the usual entry. It writes the ticket, runs the requirements-analyst once for blast radius and size, proposes a tier (`lite`, `standard`, `full`; `core/stages/feature.md` has the table), and runs the stages for that tier, stopping at every gate. `--lite`, `--standard`, or `--full` fixes the tier. The stages below are the `full` tier and can also be run one at a time:

1. `prd <slug>` with the product requirement or engineering requirement link, or `grill <slug> <idea>` first. Confirm the requirement list.
2. `handoff <slug>`. The analyst reads the code and reports conflicts and questions with defaults; answer each. The architect writes `spec.md` and `tasks.md`; confirm the task list. The spec is pinned (`spec_sha`).
3. `implement <slug>`. Per task, test-writer then implementer. Stops on a test dispute.
4. `review <slug>`. Fresh reviewer, runs the tests itself. High blast radius gets a second pass whose findings the primary rates. Loops through fixes up to `max_review_rounds` (3). Disagreements between passes are listed; you are the tiebreaker.
5. `qa <slug>`. Start the repo's DB/queues first. Acceptance per requirement, then `pr-body.md`.
6. You: `git status`, leave IDE files unstaged, commit, push, open the MR from `pr-body.md` (keep its `Feature: <slug>` line; CI reads it), merge.
7. `retro <slug>` when merged.

Where a feature is: `cat docs/features/<slug>/state.json`, or the `start` stage.

How big it is: `estimate <slug>` at any point after `ticket.md` exists. It writes `estimate.md` for an engineer driving the pipeline with agents: human hours and calendar days by stage, the parts AI does not shorten (environment testing, other teams, approvals) listed apart, a worst case made of named risks (trigger, early detection, cost), unknowns priced but not counted, and a comparison with the ticket's points, calibrated on the review rounds and calendar time of past features in the same repo. Run it when the ticket lands to challenge its points, and again after `handoff` when the task list exists.

## Scope guardrails

`core/rules/scope.md` is always on. In one paragraph: `docs/features/<slug>/ticket.md` holds the request verbatim and is the authority; every requirement carries a `source` (the ticket or a dated human decision) and the reviewer blocks on one without; agents never add behavior (a flag, fallback, job, cap, switch, message, table), they ask a one-line `[ADDS SCOPE]` question with no default and the human answers each one; findings on old code are follow-ups until a human converts them; new code must name what it reused or the grep that found nothing, and a copy of an existing implementation is a review major; the analyst gets `max_analyst_rounds` (2) then lists blockers and stops; gate questions are capped at five.

## Answering gates

Answers are recorded verbatim in `decisions.md`, with the pipeline's interpretation underneath, so a later reader can compare. Write decisions, not hints: `"Accept C-1 and Q-2. Q-1: enable for internal tenants first, capped at 100 per hour. R1-S3: waive, covered by the retry in R4."` Removing or downgrading a requirement stops the pipeline and asks; that is intended.

## Rework after APPROVE or QA

Any code change invalidates the review. Append a `## Gate: post-QA rework` entry to `decisions.md`, set `state.json.stage` to `handoff`, run `handoff` (it appends tasks and re-pins the spec), confirm, then `implement`, `review`, `qa`. Pre-existing defects the review found get their own slug after the MR (`feature <slug> --lite <idea>`), not a "later" ticket.

## When it stops

| You see | Meaning | Do |
|---|---|---|
| `stage: needs-human` | round cap, reviewer BLOCKED, or test dispute | read the top of `review-log.md` or the last history note; answer in the session |
| `VERDICT: BLOCKED` mentioning `spec_sha` | `spec.md` changed after pinning | run `handoff` again, or re-pin if the change was yours |
| `awaiting-<gate>` | the gate belongs to another role | that person runs `start` |
| a denied `git commit` | working as designed | commit yourself with `SDLC_HUMAN=1` |
| an agent states a repo fact that is wrong | project instructions or `CODEBASE.md` say so | fix the file, rerun the stage |
| `check-feature` fails in CI | not reviewed, not QA'd, spec drifted, or a report lacks evidence | the message names which; finish that stage |

## Design choices, briefly

Agents have no memory, so every stage reads and writes files under `docs/features/<slug>/`, and every role report ends with an Evidence section. When a review stops for a human (round cap, BLOCKED, a waived finding), the stage appends a one-line rule candidate to `docs/pipeline/RULE-CANDIDATES.md`; `retro` turns candidates into proposed rule edits and the human applies them, so a decision made once becomes a rule rather than a re-prompt. Reports list files read as path:line, commands with exit codes, and things looked for and not found. The reviewer never sees the implementer's reasoning and runs the tests itself. Requirement IDs run through every artifact so a missed requirement is visible. Hard caps on review rounds, task size, and agent turns. Tests are read-only for the implementer. Commit and merge are human. The research behind these choices (test tampering under pressure, reviewer bias from author claims, most findings caught by only one reviewer) is in [docs/research.md](docs/research.md), with sources.

## Contributing a fix

Change `core/` (or `adapters/claude-code/` for Claude-only metadata), bump `VERSION`, run `tests/run.sh` (needs bash, python3, jq, git; CI runs the same script), commit. The self-test builds `dist/`, installs into scratch repos (full, `--minimal`, and a migration from the old layout), re-installs to prove repo-owned files survive, and feeds known inputs to every hook and enforcement script. A change to a hook or a template needs a case there. Never edit a repo's installed copy without porting the change back here first.

## License

Apache-2.0. See [LICENSE](LICENSE).
