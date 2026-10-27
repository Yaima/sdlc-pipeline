# Gemini CLI

## What it reads

- `AGENTS.md`: Gemini reads `GEMINI.md` by default; the installed `.gemini/settings.json` sets `context.fileName` to `["AGENTS.md", "GEMINI.md"]` so the shared file is loaded. Files load hierarchically (global, then workspace and parents, then just-in-time per directory). https://github.com/google-gemini/gemini-cli/blob/main/docs/reference/configuration.md and https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/gemini-md.md
- `.agents/skills/<stage>/SKILL.md`: stage playbooks; `.agents/skills/` wins over `.gemini/skills/` in the workspace tier. Skills are on by default since v0.25. Invoke by name in the prompt ("run the prd skill for my-feature") or `/skills list`. https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/skills.md
- `.gemini/agents/<role>.md`: roles as subagents (`name`, `description`, `max_turns`; body is the system prompt). Invoke with `@code-reviewer <task>`. Subagents cannot call other subagents. https://github.com/google-gemini/gemini-cli/blob/main/docs/core/subagents.md
- `.gemini/settings.json` hooks: `BeforeTool` on `run_shell_command` and on `write_file|replace`, routed through `.claude/hooks/gemini-bridge.sh`, which converts Gemini's tool names and reply format (`{"decision":"deny","reason":...}`) to and from the shared guard scripts. Project hooks are fingerprinted; a changed hook shows a warning until re-approved. https://github.com/google-gemini/gemini-cli/blob/main/docs/hooks/reference.md

## What is enforced

- Commits, pushes, MR creation: denied by guard-git via the bridge.
- Test and config edits: guard-paths in `tests-readonly` mode on every write. Hooks are session-wide (no per-subagent hooks in the agent format), so set `SDLC_ROLE=test-writer` in the environment of the session that runs the test-writer step, or accept that the implementer's restriction applies to all roles in one session.
- Evidence gate: Gemini's `AfterAgent` deny applies to the main agent, not subagents, so evidence is checked by `check-evidence.sh` (run it on the report file, or let CI run `check-feature.sh`).
- Reviewer isolation: subagents start fresh. Do not paste `fix-notes.md`.

## Setup

1. `./install.sh /path/to/repo`, then the repo-owned edits it prints.
2. `gemini` in the repo; approve the project hooks when prompted; `/memory show` confirms `AGENTS.md` loaded; `/skills list` shows the stages; `/agents` shows the roles.
3. `ln -sf ../../docs/pipeline/enforcement/pre-commit .git/hooks/pre-commit`.
4. Run the `codebase-map` skill, correct `docs/pipeline/CODEBASE.md`, ticket branch, `start`.

## Running a feature

Same sequence: `/feature <slug> <idea>`, or the stages one at a time. When a playbook says "Run role X", say `@X slug my-feature, round N` and nothing else.

## Notes

- The policy engine (`[[rule]]` TOML) could deny `git commit` by prefix, but the workspace tier `.gemini/policies/` is documented as non-functional today, so the hook is the control. https://github.com/google-gemini/gemini-cli/blob/main/docs/reference/policy-engine.md
- `tools.exclude` is deprecated; `--allowed-tools` is deprecated in favour of `--policy`. https://github.com/google-gemini/gemini-cli/blob/main/docs/changelogs/index.md
- Custom commands (`.gemini/commands/*.toml`) still exist and are not deprecated; the pipeline uses skills instead so one file serves every tool. https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/custom-commands.md
