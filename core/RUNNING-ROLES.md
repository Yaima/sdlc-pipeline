# Running a role

Stage playbooks say "Run role `X` with slug `S`". A role is a prompt in `docs/pipeline/roles/X.md` plus a constraint: it starts with **no memory of the current conversation**. That isolation is the point, especially for `code-reviewer`. How to get it depends on the tool.

| Tool | How "Run role X" happens | Isolation |
|---|---|---|
| Claude Code | the stage skill delegates to the `X` subagent (`.claude/agents/X.md`) | automatic |
| Codex CLI | Codex spawns the `X` subagent from `.codex/agents/X.toml` (`spawn_agent`); or a fresh process: `codex exec "<role file body> Slug: S ..."` | automatic (own thread) |
| Copilot CLI / VS Code | the custom agent `X` from `.claude/agents/X.md` runs as a subagent with its own context; or `copilot --agent X -p "Slug: S ..."` | automatic |
| Copilot cloud agent | assign the `X` agent from `.github/agents/X.md` on github.com (review stage only) | automatic (new run) |
| Gemini CLI | `@X slug S, round N` uses `.gemini/agents/X.md`; subagents cannot nest | automatic |
| Any chat tool | new conversation; paste `docs/pipeline/roles/X.md`, then the slug and inputs | you provide it |

Rules for every tool:

- Pass only what the stage lists. Never paste the implementer's notes, a summary of the diff, or your own opinion into the reviewer's prompt.
- The role's reply must end with the `## Evidence` section (`docs/pipeline/rules/grounding.md`). If the tool cannot enforce that, run `docs/pipeline/enforcement/check-evidence.sh` on the report file before moving on.
- The role writes to the files the playbook names and nothing else. Outside Claude Code this is a rule, so read `git status --short` after each role run.
- When a stage runs several roles in sequence (implement: test-writer then implementer per task), each is a separate run. Do not let one context do both.

Roles: `product-manager`, `requirements-analyst`, `architect`, `test-writer`, `implementer`, `code-reviewer`, `qa-engineer`, `retro`.
