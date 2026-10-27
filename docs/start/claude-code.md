# Claude Code

## What it reads

- `CLAUDE.md`, which is one line: `@AGENTS.md`. Claude Code reads `AGENTS.md` on its own only when no `CLAUDE.md` exists, so the import keeps one instructions file for every tool. Imports resolve relative to the importing file, max 4 hops. https://code.claude.com/docs/en/memory#agents-md and https://code.claude.com/docs/en/memory#import-additional-files
- `.claude/skills/<stage>/SKILL.md`: the stage playbooks as slash commands (`/prd my-feature`). Claude Code does not read `.agents/`, so the same files are installed in both places. `$ARGUMENTS` carries the argument string. https://code.claude.com/docs/en/skills
- `.claude/agents/<role>.md`: the roles as subagents, each with its own tools, model, turn cap, and PreToolUse hooks in frontmatter. https://code.claude.com/docs/en/sub-agents
- `.claude/settings.json`: project hooks (SessionStart status, PreToolUse guard-git on Bash, PostToolUse post-edit-check, SubagentStop evidence-gate). https://code.claude.com/docs/en/hooks
- `docs/pipeline/pipeline.json`: commands and limits. Hooks read it directly.

## What is enforced

Everything in `docs/pipeline/ENFORCEMENT.md`'s Claude column: agents cannot commit or push (guard-git denies with `permissionDecision: deny`), the implementer cannot edit tests or config, the test-writer edits tests only, doc roles edit `docs/` only, the reviewer cannot read `fix-notes.md`, and a role cannot finish without an Evidence section (SubagentStop blocks twice, then marks the report unverified). Project subagent hooks run only after you accept the workspace trust dialog; a `claude -p` session does not count. https://code.claude.com/docs/en/hooks#hooks-in-skills-and-agents

## Setup

1. `./install.sh /path/to/repo` from the pipeline checkout, then the three repo-owned edits it prints (`pipeline.json`, `pipeline.local.json`, `AGENTS.md` Repo facts). `jq` on PATH.
2. `ln -sf ../../docs/pipeline/enforcement/pre-commit .git/hooks/pre-commit` (belt and braces; the Claude hooks already deny commits).
3. `claude` in the repo. Accept the workspace trust prompt. `/codebase-map`, read `docs/pipeline/CODEBASE.md`, fix what is wrong.
4. Create the ticket branch from `base_branch`. `/start`.

## Running a feature

`/feature <slug> <idea>` is the usual entry: it sizes the change (`lite`, `standard`, `full`; `--lite|--standard|--full` to fix it) and runs the stages for that tier. Stage by stage: `/prd <slug>` (or `/grill <slug> <idea>` first) → `/handoff <slug>` → `/implement <slug>` → `/review <slug>` → `/qa <slug>`. Each stage delegates to its roles automatically and stops at every gate. Answer gates as decisions; they are recorded verbatim in `decisions.md`. After `QA: PASS`, commit, push, open the MR from `pr-body.md`.

## Notes

- Custom commands (`.claude/commands/`) merged into skills; both create `/name`, the skill wins on a clash. https://code.claude.com/docs/en/skills
- `/import` copies another tool's agents, skills and MCP config into Claude Code if a teammate set up elsewhere first. https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md
- The old layout (`.claude/pipeline.json`, `.claude/rules/`) is migrated by `install.sh`; hooks fall back to the old config path.
