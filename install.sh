#!/usr/bin/env bash
# Install or update the SDLC pipeline in a target repo.
#   ./install.sh /path/to/repo            everything (works for Claude Code, Codex, Copilot, Gemini at once)
#   ./install.sh /path/to/repo --minimal  Claude Code + Copilot only (no .codex/, .gemini/, .github/)
#   ./install.sh /path/to/repo --guards-only  enforcement only: hooks, settings.json, pre-commit, CI checks, pipeline.json.
#                                             No roles, stages, or AGENTS.md changes. For a team that wants the guardrails
#                                             (tests read-only for agents, human-only commits, evidence on completion) without the process.
# Never overwrites repo-owned files: docs/pipeline/pipeline.json, pipeline.local.json, CODEBASE.md,
# the "Repo facts" part of AGENTS.md, docs/features/. The generated block in AGENTS.md is replaced in place.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DST="${1:?usage: install.sh /path/to/repo [--minimal|--guards-only]}"; MINIMAL="${2:-}"
case "$MINIMAL" in ""|--minimal|--guards-only) ;; *) echo "unknown option: $MINIMAL (use --minimal or --guards-only)" >&2; exit 1 ;; esac
GUARDS=0; [ "$MINIMAL" = "--guards-only" ] && GUARDS=1
[ -d "$DST/.git" ] || { echo "not a git repo: $DST" >&2; exit 1; }
command -v jq >/dev/null || echo "warning: jq not on PATH; hooks and checks need it"
python3 "$HERE/build.py" >/dev/null
SRC="$HERE/dist"

mkdir -p "$DST/docs/pipeline"
# migrate the pre-2026.09.29 layout
if [ -f "$DST/.claude/pipeline.json" ] && [ ! -f "$DST/docs/pipeline/pipeline.json" ]; then
  mv "$DST/.claude/pipeline.json" "$DST/docs/pipeline/pipeline.json"; echo "moved .claude/pipeline.json -> docs/pipeline/pipeline.json"
fi
[ -f "$DST/.claude/pipeline.local.json" ] && [ ! -f "$DST/docs/pipeline/pipeline.local.json" ] && mv "$DST/.claude/pipeline.local.json" "$DST/docs/pipeline/pipeline.local.json"
[ -f "$DST/docs/pipeline/pipeline.local.json" ] || cp "$HERE/core/templates/pipeline.local.json" "$DST/docs/pipeline/pipeline.local.json"


new_files=()
while IFS= read -r rel; do
  case "$rel" in
    AGENTS.md.sdlc|AGENTS.md.template) continue ;;
    docs/features/*) [ -e "$DST/$rel" ] && continue ;;
    docs/pipeline/pipeline.json|CLAUDE.md) [ -e "$DST/$rel" ] && continue; new_files+=("$rel") ;;
    .codex/*|.gemini/*|.github/*) [ "$MINIMAL" = "--minimal" ] && continue ;;
  esac
  if [ "$GUARDS" -eq 1 ]; then
    case "$rel" in
      .claude/hooks/*|.claude/settings.json|docs/pipeline/enforcement/*|docs/pipeline/pipeline.json|docs/pipeline/ENFORCEMENT.md|docs/pipeline/VERSION) ;;
      *) continue ;;
    esac
  fi
  mkdir -p "$DST/$(dirname "$rel")"; cp -p "$SRC/$rel" "$DST/$rel"
done < <(cd "$SRC" && find . -type f | sed 's#^\./##')
chmod +x "$DST"/.claude/hooks/*.sh "$DST"/docs/pipeline/enforcement/*.sh "$DST"/docs/pipeline/enforcement/pre-commit

# AGENTS.md: create from template, or replace the generated block between the sdlc markers
if [ "$GUARDS" -eq 1 ]; then
  : # guards-only leaves project instructions alone
elif [ ! -f "$DST/AGENTS.md" ]; then
  cp "$SRC/AGENTS.md.template" "$DST/AGENTS.md"; new_files+=("AGENTS.md")
elif grep -q '<!-- sdlc:begin' "$DST/AGENTS.md"; then
  python3 - "$DST/AGENTS.md" "$SRC/AGENTS.md.sdlc" <<'EOF'
import re,sys
p,blk=sys.argv[1],open(sys.argv[2]).read()
s=open(p).read()
s=re.sub(r'<!-- sdlc:begin.*?<!-- sdlc:end -->\n?', blk, s, flags=re.S)
open(p,'w').write(s)
EOF
else
  printf '\n' >> "$DST/AGENTS.md"; cat "$SRC/AGENTS.md.sdlc" >> "$DST/AGENTS.md"
  echo "appended the pipeline block to the existing AGENTS.md"
fi
# a CLAUDE.md from the old layout (full text) becomes AGENTS.md's Repo facts if AGENTS.md was just created
if [ "$GUARDS" -eq 0 ] && [ -f "$DST/CLAUDE.md" ] && ! grep -qx '@AGENTS.md' "$DST/CLAUDE.md"; then
  if grep -q '## Repo facts' "$DST/CLAUDE.md"; then
    python3 - "$DST/CLAUDE.md" "$DST/AGENTS.md" <<'EOF'
import re,sys
c=open(sys.argv[1]).read(); a=open(sys.argv[2]).read()
m=re.search(r'## Repo facts\n.*?(?=\n## |\Z)', c, re.S)
if m and '<!-- Rewrite this section' in a:
    a=re.sub(r'## Repo facts\n.*?(?=\n## |\Z)', m.group(0), a, count=1, flags=re.S); open(sys.argv[2],'w').write(a)
    print("moved Repo facts from CLAUDE.md into AGENTS.md")
EOF
  fi
  cp "$SRC/CLAUDE.md" "$DST/CLAUDE.md"; echo "CLAUDE.md now imports AGENTS.md (old content preserved in git history)"
fi

[ "$GUARDS" -eq 0 ] && [ -d "$DST/.claude/rules" ] && { rm -rf "$DST/.claude/rules"; echo "removed .claude/rules (rules now live in docs/pipeline/rules/)"; }
# guards-only: no per-role subagents exist, so the path guard runs session-wide on edits (SDLC_ROLE picks the mode)
if [ "$GUARDS" -eq 1 ]; then
  python3 - "$DST/.claude/settings.json" <<'EOF3'
import json,sys
p=sys.argv[1]; s=json.load(open(p))
pre=s.setdefault("hooks",{}).setdefault("PreToolUse",[])
if not any(h.get("matcher","").startswith("Edit") for h in pre):
    pre.append({"matcher":"Edit|Write|MultiEdit|NotebookEdit","hooks":[{"type":"command","command":"${CLAUDE_PROJECT_DIR}/.claude/hooks/guard-paths.sh tests-readonly"}]})
json.dump(s,open(p,"w"),indent=2); open(p,"a").write("\n")
EOF3
fi
# .claude/settings.json: pre-approve the repo's own commands so agents run them without prompts (edit pipeline.json, re-run install)
python3 - "$DST/.claude/settings.json" "$DST/docs/pipeline/pipeline.json" <<'EOF2'
import json,sys
sp,pp=sys.argv[1],sys.argv[2]; s=json.load(open(sp)); c=json.load(open(pp))
allow=["Bash(git status:*)","Bash(git diff:*)","Bash(git log:*)","Bash(git show:*)","Bash(git branch:*)","Bash(git ls-files:*)","Bash(git hash-object:*)","Bash(git stash create)","Bash(git worktree:*)"]
def rules(v):
    v=(v or "").strip()
    if not v: return []
    if "{file}" in v:                      # placeholder commands: allow the prefix before the placeholder
        pre=v.split("{file}",1)[0].strip()
        return [f"Bash({pre}:*)"] if pre else []
    return [f"Bash({v})", f"Bash({v}:*)"]
for k in ("test_cmd","test_file_cmd","lint_cmd","typecheck_cmd","security_cmd","format_cmd","coverage_cmd"):
    allow += rules(c.get(k))
for ext,cfg in (c.get("languages") or {}).items():
    for k in ("test_cmd","lint_cmd","format_cmd"):
        allow += rules(cfg.get(k))
s.setdefault("permissions",{})["allow"]=list(dict.fromkeys(allow))
json.dump(s,open(sp,"w"),indent=2); open(sp,"a").write("\n")
EOF2
for line in 'docs/pipeline/pipeline.local.json' '.claude/settings.local.json' '.codex/config.local.toml' 'junit*.xml'; do
  grep -qxF "$line" "$DST/.gitignore" 2>/dev/null || echo "$line" >> "$DST/.gitignore"
done
# pipeline.json: add the protected globs this layout needs, keep everything else
python3 - "$DST/docs/pipeline/pipeline.json" "$HERE/core/pipeline.json" <<'EOF'
import json,sys
p=sys.argv[1]; c=json.load(open(p)); t=json.load(open(sys.argv[2]))
g=list(dict.fromkeys(c.get('protected_config_globs',[])+t['protected_config_globs']));
if g!=c.get('protected_config_globs'): c['protected_config_globs']=g; json.dump(c,open(p,'w'),indent=2); open(p,'a').write('\n')
EOF

echo "installed sdlc-pipeline $(cat "$HERE/VERSION") into $DST${GUARDS:+ }$([ "$GUARDS" -eq 1 ] && echo '(guards only)')"
if [ "$GUARDS" -eq 1 ]; then cat <<MSG
Guards installed: .claude/hooks (git guard, path guard, evidence gate), .claude/settings.json, docs/pipeline/enforcement, docs/pipeline/pipeline.json.
Then:
  1. docs/pipeline/pipeline.json: test_cmd, lint_cmd, security_cmd, test_globs, protected_config_globs, protected_branches, base_branch. Re-run install after changes (it regenerates the permission allowlist).
  2. ln -sf ../../docs/pipeline/enforcement/pre-commit .git/hooks/pre-commit; SDLC_HUMAN=1 when you commit.
  3. CI: docs/pipeline/enforcement/ci/ (optional without the process; check-evidence.sh works on any report file).
  What each guard does: docs/pipeline/ENFORCEMENT.md. Add the full pipeline later with ./install.sh $DST (repo-owned files are kept).
MSG
elif [ ${#new_files[@]} -gt 0 ]; then cat <<MSG

New repo-owned files; edit by hand:
$(printf '  - %s\n' "${new_files[@]}")
Then:
  1. docs/pipeline/pipeline.json: test_cmd, lint_cmd, typecheck_cmd, security_cmd, coverage_cmd, base_branch, pr_tool (match the Makefile/CI).
  2. docs/pipeline/pipeline.local.json: your name and role.
  3. AGENTS.md "Repo facts": rewrite from the repo. Agents treat every line as true.
  4. ln -sf ../../docs/pipeline/enforcement/pre-commit .git/hooks/pre-commit
  5. Your tool's start guide: docs/start/<tool>.md. Then run /codebase-map, correct docs/pipeline/CODEBASE.md, and /start.
MSG
else echo "repo-owned files left untouched; read docs/start/<tool>.md if the layout changed for you"; fi
