# GitHub Copilot

Three surfaces read this repo: Copilot CLI (terminal), Copilot in VS Code (agent mode, through the "Agent Host"), and the Copilot cloud agent (formerly "coding agent"; runs on github.com and opens PRs). They read different files.

## What it reads

CLI and VS Code:
- `AGENTS.md` at the root and nested; `CLAUDE.md` too, with `@path` imports expanded. https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference and https://docs.github.com/en/copilot/reference/custom-instructions-support
- `.agents/skills/<stage>/SKILL.md` (also `.claude/skills/`): stage playbooks, invoked as `/prd my-feature`. Prompt files (`.github/prompts/*.prompt.md`) are deprecated for Agent Host sessions; skills replace them. https://docs.github.com/en/copilot/concepts/agents/about-agent-skills and https://code.visualstudio.com/docs/agent-customization/prompt-files
- `.claude/agents/<role>.md`: roles as custom agents; Copilot reads the Claude sub-agent format from this directory. A custom agent runs as a subagent with its own context window. https://code.visualstudio.com/docs/agent-customization/custom-agents and https://docs.github.com/en/copilot/concepts/agents/copilot-cli/about-custom-agents
- `.claude/settings.json` hooks: the CLI loads them (PascalCase events accepted, Claude tool names mapped). In VS Code the Copilot harness behaves like the CLI; the "Local" harness needs `chat.useClaudeHooks`. https://docs.github.com/en/copilot/reference/hooks-reference and https://code.visualstudio.com/docs/agent-customization/hooks

Cloud agent (github.com):
- `AGENTS.md`; `.github/agents/<role>.md` (its own agent format, generated from the same roles); `.github/hooks/sdlc.json` (must be on the default branch; only `bash` entries run). It does not read `.claude/`. https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/use-hooks and https://docs.github.com/en/copilot/reference/custom-agents-configuration

## What is enforced

- CLI and VS Code (Copilot harness): commits denied by guard-git; test and config edits by guard-paths; evidence by the subagentStop hook; reviewer isolation by the subagent's own context. Per-role guard-paths hooks live in the agent frontmatter, which VS Code honours (Preview) and the CLI documentation does not mention: treat per-role scoping as a rule on the CLI, and set `SDLC_ROLE` as described in `docs/pipeline/ENFORCEMENT.md` when it matters.
- Cloud agent: guard-git and guard-paths run from `.github/hooks/sdlc.json` before every tool call; `ask` is treated as `deny` there. The cloud agent always commits to its own PR branch, so the pipeline's human-commit rule does not apply to it; use it only for the `review` stage (a fresh reviewer on a PR) and for `codebase-map`, not for `implement`.
- A CLI subagent does not receive repo instructions unless its frontmatter sets `include-custom-instructions: true`; the generated role files set it so roles see the pipeline rules. https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference

## Setup

1. `./install.sh /path/to/repo`, then the repo-owned edits it prints.
2. CLI: `copilot` in the repo; `/instructions` shows what loaded, `/skills list` shows the stages, `/agent` lists the roles, `/env` shows the hooks. VS Code: open the folder; the `/` menu lists the stage skills; pick a role agent from the agent picker for a fresh-context run.
3. `ln -sf ../../docs/pipeline/enforcement/pre-commit .git/hooks/pre-commit`.
4. `/codebase-map`, correct `docs/pipeline/CODEBASE.md`, ticket branch, `/start`.

## Running a feature

`/feature <slug> <idea>` sizes the change and runs the tier's stages; stage by stage it is `/prd`, `/handoff`, `/implement`, `/review`, `/qa` with the slug. When a playbook says "Run role X", the CLI dispatches the custom agent as a subagent. To force a fresh reviewer yourself: `copilot --agent code-reviewer -p "Slug: my-feature, round 1"`.

## Notes

- Names changed in 2026: "coding agent" is "cloud agent"; `.chatmode.md` files are retired in favour of `.agent.md`; `excludeAgent` values are `code-review` and `cloud-agent`. https://code.visualstudio.com/docs/agent-customization/custom-agents
- Skills can be installed from a registry with `gh skill` (public preview) and pre-approve tools with `allowed-tools`. https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills
- The docs disagree on whether a user-level agent beats a repo agent of the same name; keep role names unique to this pipeline.
