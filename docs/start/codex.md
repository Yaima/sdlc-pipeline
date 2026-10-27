# Codex CLI

Codex docs moved: `developers.openai.com/codex/*` redirects to `learn.chatgpt.com/docs/*`. All links below are the current location.

## What it reads

- `AGENTS.md` at the repo root (and nested ones, root-down, deeper wins). Default combined cap is 32 KiB; the pipeline block is about 6 KiB; `.codex/config.toml` raises `project_doc_max_bytes` so long Repo facts never hit the cap. https://learn.chatgpt.com/docs/agent-configuration/agents-md
- `.agents/skills/<stage>/SKILL.md`: stage playbooks. Codex scans `.agents/skills` from cwd up to the repo root. Invoke as `$prd my-feature` in the prompt, or `/skills`. Custom prompts (`~/.codex/prompts`) are deprecated; skills replace them. https://learn.chatgpt.com/docs/build-skills and https://learn.chatgpt.com/docs/custom-prompts
- `.codex/agents/<role>.toml`: roles as native subagents (`name`, `description`, `developer_instructions`). Codex spawns them with `spawn_agent` when a playbook says "Run role X". `/agent` switches threads. https://learn.chatgpt.com/docs/agent-configuration/subagents
- `.codex/hooks.json`: PreToolUse on `Bash` (guard-git) and on `apply_patch` (guard-paths), SubagentStop (evidence-gate), SessionStart (status). Same JSON deny protocol as Claude Code, same scripts. https://learn.chatgpt.com/docs/hooks
- `.codex/config.toml`: `project_doc_max_bytes`, `sandbox_mode = "workspace-write"`. Project config loads only for trusted projects. https://learn.chatgpt.com/docs/config-file/config-advanced#project-config-files-codexconfigtoml

## What is enforced

- Commits, pushes, MR creation: denied by guard-git through the PreToolUse hook.
- Test and config edits: guard-paths runs on every `apply_patch` in `tests-readonly` mode (the implementer's mode), extracting file paths from the patch text. This is the one place Codex is coarser than Claude Code: hooks are session-wide, not per subagent, so the test-writer role hits the same deny when it edits tests. Workaround in the implement playbook for Codex: run the test-writer with `SDLC_ROLE=test-writer` in the environment of a separate `codex exec` process, where the hook is bypassed by the env check in guard-paths. See "Role scoping" below.
- Evidence: SubagentStop blocks a role report without Evidence, test command and exit codes.
- Reviewer isolation: `spawn_agent` subagents start fresh. Never paste `fix-notes.md` into the prompt.

## Setup

1. `./install.sh /path/to/repo`, then the repo-owned edits it prints.
2. Mark the project trusted so `.codex/` loads: in `~/.codex/config.toml`, `projects."/abs/path/to/repo".trust_level = "trusted"`. https://learn.chatgpt.com/docs/config-file/config-reference
3. `codex` in the repo, then `/hooks` to review and trust the project hooks (hash-based; a changed hook needs re-trust). https://learn.chatgpt.com/docs/hooks
4. `ln -sf ../../docs/pipeline/enforcement/pre-commit .git/hooks/pre-commit`.
5. `$codebase-map`, read `docs/pipeline/CODEBASE.md`, correct it. Ticket branch. `$start`.

## Running a feature

`$feature my-feature <idea>` sizes the change and runs the tier's stages (`--lite|--standard|--full` to fix the tier). Stage by stage: `$prd my-feature` → `$handoff my-feature` → `$implement my-feature` → `$review my-feature` → `$qa my-feature`. When a playbook says "Run role code-reviewer", tell Codex "spawn the code-reviewer agent with slug my-feature and round N; pass nothing else". Non-interactive alternative for a fully fresh process: `codex exec --sandbox workspace-write "$(cat .codex/agents/code-reviewer.toml | sed -n '/developer_instructions/,$p')  Slug: my-feature, round 1"`. https://learn.chatgpt.com/docs/non-interactive-mode

## Role scoping

`guard-paths.sh` honours `SDLC_ROLE`: `test-writer` may edit tests, `docs` roles may edit only docs. Codex subagents inherit the parent environment, so set it per process: `SDLC_ROLE=test-writer codex exec ...` for the test-writing step of a task, plain `codex` for the implementer. In an interactive session without that split, the implementer's restriction applies to everyone, which is the safe direction.

## Notes

- `approval_policy` values are `on-request`, `never`, or a granular table; `untrusted` and `on-failure` are gone. `--full-auto` is deprecated; use `--sandbox workspace-write`. https://learn.chatgpt.com/docs/config-file/config-reference
- `execpolicy` `.rules` files (`.codex/rules/`) can also forbid `git commit` by prefix; they are marked experimental, so the hook is the primary control. https://learn.chatgpt.com/docs/agent-configuration/rules
- `/import` migrates a Claude Code setup into Codex if a teammate started there. https://learn.chatgpt.com/docs/developer-commands?surface=cli
