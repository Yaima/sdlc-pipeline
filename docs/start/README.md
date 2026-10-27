# Start guides

One page per tool. Each says what the tool reads from this repo, what it enforces, the setup steps, and how a feature runs. Facts were checked against the tools' official docs on 2026-09-29; every non-obvious claim carries its source. Where a tool's docs were unclear, the guide says so. Claude Code is the primary target; Codex and Copilot CLI have run full features; Gemini and the Copilot cloud agent are documentation-checked. These tools change their config formats often. When the check date above is more than six months old, re-read the linked source before relying on an enforcement claim, and open an issue if it moved.

| Tool | Guide | Reads natively | Enforcement |
|---|---|---|---|
| Claude Code | [claude-code.md](claude-code.md) | `CLAUDE.md` → `AGENTS.md`, `.claude/skills`, `.claude/agents`, `.claude/settings.json` hooks | full |
| Codex CLI | [codex.md](codex.md) | `AGENTS.md`, `.agents/skills`, `.codex/agents`, `.codex/hooks.json` | full for commits and file edits; role scoping partial |
| GitHub Copilot | [copilot.md](copilot.md) | `AGENTS.md`, `.agents/skills`, `.claude/agents`, `.claude/settings.json` hooks (CLI, VS Code); `.github/agents`, `.github/hooks` (cloud agent) | full on CLI; cloud agent partial |
| Gemini CLI | [gemini.md](gemini.md) | `AGENTS.md` (via `.gemini/settings.json`), `.agents/skills`, `.gemini/agents`, hooks in `.gemini/settings.json` | commits and edits enforced via the bridge; no per-role scoping |
| Anything else | [other-tools.md](other-tools.md) | whatever it reads; paste `AGENTS.md` | git pre-commit and CI only |

Common to all: `docs/pipeline/` holds the process, `docs/features/<slug>/` holds each feature, humans commit and merge, and the git pre-commit plus `check-feature.sh` in CI apply regardless of tool (`docs/pipeline/ENFORCEMENT.md`).
