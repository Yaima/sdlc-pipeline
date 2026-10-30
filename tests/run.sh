#!/usr/bin/env bash
# Self-test for the pipeline repo. Run from anywhere: tests/run.sh
# Builds dist/, installs into scratch git repos, checks the installed tree, and runs every
# enforcement script and hook against known inputs. Exit 1 on the first group with a failure.
# Needs: bash, python3, jq, git.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); }
ko()  { fail=$((fail+1)); echo "  FAIL: $*" >&2; }
# t <description> <command...>   passes when the command exits 0
t()   { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok; else ko "$d"; fi; }
# tf <description> <command...>  passes when the command exits non-zero
tf()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ko "$d (expected failure)"; else ok; fi; }
group() { echo "== $1"; }
VERSION=$(cat "$HERE/VERSION")
ROLES=$(ls "$HERE/core/roles" | sed 's/\.md$//')
STAGES="start codebase-map grill estimate prd handoff implement review qa feature roadmap retro"

group "source files"
for f in adapters/claude-code/agents.json adapters/claude-code/settings.json adapters/claude-code/stages.json \
         core/pipeline.json core/templates/pipeline.local.json core/templates/state.json; do
  t "valid JSON: $f" jq empty "$HERE/$f"
done
for r in $ROLES; do
  t "agents.json has metadata for role $r" jq -e --arg r "$r" '.[$r]' "$HERE/adapters/claude-code/agents.json"
  t "role file starts with '# Role:': $r" grep -q '^# Role:' "$HERE/core/roles/$r.md"
done
for s in $STAGES; do t "stage playbook exists: $s" test -f "$HERE/core/stages/$s.md"; done
t "VERSION is a date" grep -Eq '^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$' "$HERE/VERSION"
for sh in "$HERE"/adapters/claude-code/hooks/*.sh "$HERE"/core/enforcement/*.sh "$HERE"/core/enforcement/pre-commit "$HERE"/install.sh; do
  t "bash -n $(basename "$sh")" bash -n "$sh"
done
t "build.py compiles" python3 -m py_compile "$HERE/build.py"
t "board design: contrast check passes (WCAG 2.2 AA, both themes)" python3 "$HERE/board/design/check-contrast.py"
t "board design: components.css holds no color literals" bash -c "! grep -En '#[0-9a-fA-F]{3,8}\b|rgb\(' '$HERE/board/design/components.css'"

group "build"
t "build.py runs" python3 "$HERE/build.py"
D="$HERE/dist"
t "dist/CLAUDE.md imports AGENTS.md" grep -qx '@AGENTS.md' "$D/CLAUDE.md"
t "AGENTS.md.sdlc has begin marker with version" grep -q "<!-- sdlc:begin $VERSION" "$D/AGENTS.md.sdlc"
t "AGENTS.md.sdlc has end marker" grep -q '<!-- sdlc:end -->' "$D/AGENTS.md.sdlc"
t "AGENTS.md.template has Repo facts" grep -q '^## Repo facts' "$D/AGENTS.md.template"
for r in $ROLES; do
  for f in ".claude/agents/$r.md" ".codex/agents/$r.toml" ".gemini/agents/$r.md" ".github/agents/$r.md"; do
    t "built: $f" test -s "$D/$f"
  done
  t "claude agent $r has frontmatter name" grep -q "^name: $r$" "$D/.claude/agents/$r.md"
done
for s in $STAGES; do
  t "built: .agents/skills/$s/SKILL.md" test -s "$D/.agents/skills/$s/SKILL.md"
  t "built: .claude/skills/$s/SKILL.md" test -s "$D/.claude/skills/$s/SKILL.md"
  t "skill $s has no unexpanded {slug}" bash -c "! grep -q '{slug}' '$D/.claude/skills/$s/SKILL.md'"
done
for f in .claude/settings.json .codex/hooks.json .gemini/settings.json .github/hooks/sdlc.json docs/pipeline/pipeline.json; do
  t "valid JSON: dist/$f" jq empty "$D/$f"
done
for h in "$D"/.claude/hooks/*.sh; do t "hook executable: $(basename "$h")" test -x "$h"; done
t "dist VERSION matches" bash -c "[ \"\$(cat '$D/docs/pipeline/VERSION')\" = '$VERSION' ]"
t "dist carries ENFORCEMENT.md" test -s "$D/docs/pipeline/ENFORCEMENT.md"
t "dist carries start guides" test -s "$D/docs/start/claude-code.md"
t "AGENTS.md block stays under 8 KB (rule bodies load on demand)" bash -c "[ \"\$(wc -c < '$D/AGENTS.md.sdlc')\" -lt 8192 ]"
t "AGENTS.md block points at the rule files" grep -q 'docs/pipeline/rules/grounding.md' "$D/AGENTS.md.sdlc"
t "test-writer runs on opus" grep -q '^model: opus$' "$D/.claude/agents/test-writer.md"
t "feature skill documents the three tiers" bash -c "grep -q '\`lite\`' '$D/.claude/skills/feature/SKILL.md' && grep -q '\`standard\`' '$D/.claude/skills/feature/SKILL.md' && grep -q '\`full\`' '$D/.claude/skills/feature/SKILL.md'"

mkrepo() {  # mkrepo <dir>: empty git repo with one commit on a feature branch
  git init -q -b feature/scratch "$1" && git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
}

group "install (full)"
R="$TMP/full"; mkrepo "$R"
t "install.sh exits 0" "$HERE/install.sh" "$R"
t "AGENTS.md created" test -s "$R/AGENTS.md"
t "AGENTS.md has pipeline block" grep -q '<!-- sdlc:begin' "$R/AGENTS.md"
t "CLAUDE.md imports AGENTS.md" grep -qx '@AGENTS.md' "$R/CLAUDE.md"
t "installed VERSION matches" bash -c "[ \"\$(cat '$R/docs/pipeline/VERSION')\" = '$VERSION' ]"
t "pipeline.json installed" jq empty "$R/docs/pipeline/pipeline.json"
t "pipeline.local.json installed" jq empty "$R/docs/pipeline/pipeline.local.json"
for f in docs/pipeline/pipeline.local.json .claude/settings.local.json .codex/config.local.toml 'junit*.xml'; do
  t ".gitignore has $f" grep -qxF "$f" "$R/.gitignore"
done
for d in .claude/agents .claude/skills .agents/skills .claude/hooks .codex/agents .gemini/agents .github/agents .github/hooks docs/pipeline/enforcement docs/features; do
  t "installed dir: $d" test -d "$R/$d"
done
t "pre-commit executable" test -x "$R/docs/pipeline/enforcement/pre-commit"
t "check-feature.sh executable" test -x "$R/docs/pipeline/enforcement/check-feature.sh"
tf "install.sh refuses a non-git dir" "$HERE/install.sh" "$TMP"

group "install (re-run keeps repo-owned files)"
sed -i.bak 's/^- Stack: .*/- Stack: KEEPME stack line/' "$R/AGENTS.md" && rm -f "$R/AGENTS.md.bak"
jq '.test_cmd="make test" | .base_branch="develop"' "$R/docs/pipeline/pipeline.json" > "$TMP/pj" && mv "$TMP/pj" "$R/docs/pipeline/pipeline.json"
echo '{"name":"me","role":"solo"}' > "$R/docs/pipeline/pipeline.local.json"
t "second install.sh exits 0" "$HERE/install.sh" "$R"
t "Repo facts edit survived" grep -q 'KEEPME stack line' "$R/AGENTS.md"
t "exactly one sdlc:begin marker" bash -c "[ \"\$(grep -c '<!-- sdlc:begin' '$R/AGENTS.md')\" = 1 ]"
t "pipeline.json test_cmd survived" bash -c "[ \"\$(jq -r .test_cmd '$R/docs/pipeline/pipeline.json')\" = 'make test' ]"
t "pipeline.json base_branch survived" bash -c "[ \"\$(jq -r .base_branch '$R/docs/pipeline/pipeline.json')\" = 'develop' ]"
t "pipeline.local.json survived" bash -c "[ \"\$(jq -r .name '$R/docs/pipeline/pipeline.local.json')\" = 'me' ]"
t ".gitignore lines not duplicated" bash -c "[ \"\$(grep -cxF 'docs/pipeline/pipeline.local.json' '$R/.gitignore')\" = 1 ]"
t "settings.json allows test_cmd" jq -e '.permissions.allow | index("Bash(make test:*)")' "$R/.claude/settings.json"
t "settings.json allows read-only git" jq -e '.permissions.allow | index("Bash(git diff:*)")' "$R/.claude/settings.json"
jq '.security_cmd="gosec ./..."' "$R/docs/pipeline/pipeline.json" > "$TMP/pj" && mv "$TMP/pj" "$R/docs/pipeline/pipeline.json"
t "third install exits 0" "$HERE/install.sh" "$R"
t "settings.json allows security_cmd" jq -e '.permissions.allow | index("Bash(gosec ./...:*)")' "$R/.claude/settings.json"
jq '.security_cmd=""' "$R/docs/pipeline/pipeline.json" > "$TMP/pj" && mv "$TMP/pj" "$R/docs/pipeline/pipeline.json"
tf "settings.json does not allow git commit" jq -e '.permissions.allow | map(select(startswith("Bash(git commit"))) | length > 0' "$R/.claude/settings.json"
t "settings.json keeps the hooks" jq -e '.hooks.PreToolUse' "$R/.claude/settings.json"

group "install (--minimal)"
M="$TMP/minimal"; mkrepo "$M"
t "install.sh --minimal exits 0" "$HERE/install.sh" "$M" --minimal
t "minimal has .claude/agents" test -d "$M/.claude/agents"
tf "minimal has no .codex" test -e "$M/.codex"
tf "minimal has no .gemini" test -e "$M/.gemini"
tf "minimal has no .github" test -e "$M/.github"

group "install (--guards-only)"
G="$TMP/guards"; mkrepo "$G"
t "install.sh --guards-only exits 0" "$HERE/install.sh" "$G" --guards-only
t "guards: hooks present" test -x "$G/.claude/hooks/guard-git.sh"
t "guards: settings.json valid" jq empty "$G/.claude/settings.json"
t "guards: session-wide path guard added" jq -e '.hooks.PreToolUse[] | select(.matcher|startswith("Edit")) | .hooks[0].command | test("guard-paths.sh tests-readonly")' "$G/.claude/settings.json"
t "guards: git guard kept" jq -e '.hooks.PreToolUse[] | select(.matcher=="Bash")' "$G/.claude/settings.json"
t "guards: enforcement scripts present" test -x "$G/docs/pipeline/enforcement/pre-commit"
t "guards: pipeline.json present" jq empty "$G/docs/pipeline/pipeline.json"
t "guards: ENFORCEMENT.md present" test -s "$G/docs/pipeline/ENFORCEMENT.md"
tf "guards: no AGENTS.md" test -e "$G/AGENTS.md"
tf "guards: no CLAUDE.md" test -e "$G/CLAUDE.md"
tf "guards: no agents" test -e "$G/.claude/agents"
tf "guards: no skills" test -e "$G/.claude/skills"
tf "guards: no .codex" test -e "$G/.codex"
tf "guards: no roles docs" test -e "$G/docs/pipeline/roles"
t "guards: upgrade to full keeps pipeline.json" bash -c "jq '.test_cmd=\"go test ./...\"' '$G/docs/pipeline/pipeline.json' > '$TMP/gj' && mv '$TMP/gj' '$G/docs/pipeline/pipeline.json' && '$HERE/install.sh' '$G' >/dev/null && [ \"\$(jq -r .test_cmd '$G/docs/pipeline/pipeline.json')\" = 'go test ./...' ] && [ -f '$G/AGENTS.md' ]"
tf "install.sh rejects an unknown option" "$HERE/install.sh" "$G" --bogus

group "install (migration from the old layout)"
O="$TMP/old"; mkrepo "$O"
mkdir -p "$O/.claude/rules"; echo '{"test_cmd":"go test ./...","protected_config_globs":["Makefile"]}' > "$O/.claude/pipeline.json"
printf '# Old\n\n## Repo facts\n\n- Stack: OLDFACT go\n\n## Other\n\ntext\n' > "$O/CLAUDE.md"; echo 'x' > "$O/.claude/rules/r.md"
t "install.sh on old layout exits 0" "$HERE/install.sh" "$O"
t "pipeline.json moved" test -f "$O/docs/pipeline/pipeline.json"
tf ".claude/pipeline.json gone" test -e "$O/.claude/pipeline.json"
t "old test_cmd kept" bash -c "[ \"\$(jq -r .test_cmd '$O/docs/pipeline/pipeline.json')\" = 'go test ./...' ]"
t "protected globs merged" jq -e '.protected_config_globs | index("Makefile") and index("AGENTS.md")' "$O/docs/pipeline/pipeline.json"
t "Repo facts moved into AGENTS.md" grep -q 'OLDFACT' "$O/AGENTS.md"
t "CLAUDE.md now imports AGENTS.md" grep -qx '@AGENTS.md' "$O/CLAUDE.md"
tf ".claude/rules removed" test -e "$O/.claude/rules"

# Hook and script tests run inside the full install, which has test_cmd "make test".
export CLAUDE_PROJECT_DIR="$R"
H="$R/.claude/hooks"; E="$R/docs/pipeline/enforcement"
hook() { printf '%s' "$2" | "$H/$1" "${@:3}"; }  # hook <script> <json> [args]
denies() { hook "$@" 2>/dev/null | grep -q '"permissionDecision": *"deny"'; }
allows() { local out; out=$(hook "$@" 2>/dev/null) && ! printf '%s' "$out" | grep -q '"deny"'; }

group "guard-git.sh (commit_mode human)"
gg() { printf '{"tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')" | "$H/guard-git.sh" >/dev/null 2>&1; }
tf "denies git commit" gg "git commit -m x"
tf "denies git push" gg "git push origin feature/x"
tf "denies gh pr create" gg "gh pr create --fill"
tf "denies glab mr create" gg "glab mr create"
tf "denies git rebase" gg "git rebase develop"
t  "allows git status" gg "git status --short"
t  "allows git diff" gg "git diff --stat"
t  "allows make test" gg "make test"
t  "allows empty command" bash -c "printf '{}' | '$H/guard-git.sh'"

group "guard-git.sh (commit_mode agent)"
jq '.commit_mode="agent"' "$R/docs/pipeline/pipeline.json" > "$TMP/pj" && mv "$TMP/pj" "$R/docs/pipeline/pipeline.json"
t  "allows git commit" gg "git commit -m x"
t  "allows push to feature branch" gg "git push origin feature/x"
tf "denies push to main" gg "git push origin main"
tf "denies push to develop" gg "git push origin develop"
tf "denies push to release/*" gg "git push origin release/1.2"
tf "denies force push" gg "git push --force origin feature/x"
tf "denies gh pr merge" gg "gh pr merge 12"
tf "denies glab mr approve" gg "glab mr approve 12"
tf "denies git reset --hard" gg "git reset --hard HEAD~1"
tf "denies git branch -D" gg "git branch -D feature/x"
t  "rm -rf outside scratch asks, not denies" bash -c "printf '%s' '{\"tool_input\":{\"command\":\"rm -rf src\"}}' | '$H/guard-git.sh' | grep -q '\"permissionDecision\": *\"ask\"'"
t  "rm -rf node_modules passes silently" bash -c "[ -z \"\$(printf '%s' '{\"tool_input\":{\"command\":\"rm -rf node_modules\"}}' | '$H/guard-git.sh')\" ]"
jq '.commit_mode="human"' "$R/docs/pipeline/pipeline.json" > "$TMP/pj" && mv "$TMP/pj" "$R/docs/pipeline/pipeline.json"

group "guard-git.sh (adversarial: ways around the rules)"
jq '.commit_mode="human"' "$R/docs/pipeline/pipeline.json" > "$TMP/pj" && mv "$TMP/pj" "$R/docs/pipeline/pipeline.json"
tf "inline alias to commit" gg "git -c alias.ci=commit ci -m x"
tf "inline alias with space" gg "git -c  alias.p=push p origin feature/x"
tf "core.hooksPath override" gg "git -c core.hooksPath=/dev/null status"
tf "--no-verify" gg "git commit --no-verify -m x"
tf "git config alias" gg "git config alias.ci commit"
tf "git config hooksPath" gg "git config core.hooksPath .nohooks"
tf "command builtin prefix" gg "command git push origin feature/x"
tf "sh -c wrapper" gg "sh -c 'git commit -m x'"
tf "env prefix" gg "GIT_AUTHOR_NAME=x git commit -m x"
tf "chained after a harmless command" gg "git status && git push origin feature/x"
tf "piped" gg "echo y | git commit -F -"
tf "gh pr create in a subshell" gg "(cd . && gh pr create --fill)"
jq '.commit_mode="agent"' "$R/docs/pipeline/pipeline.json" > "$TMP/pj" && mv "$TMP/pj" "$R/docs/pipeline/pipeline.json"
tf "push HEAD:main refspec" gg "git push origin HEAD:main"
tf "push +refs/heads/main" gg "git push origin +refs/heads/main"
tf "push refs/heads/develop" gg "git push origin feature/x:refs/heads/develop"
tf "push --force-with-lease" gg "git push --force-with-lease origin feature/x"
tf "push -f short flag" gg "git push -f origin feature/x"
tf "push release/* branch" gg "git push origin HEAD:release/2.0"
t  "push to a feature branch still allowed" gg "git push origin feature/x:feature/x"
t  "push to a branch that merely contains 'main'" gg "git push origin feature/maintenance"
jq '.commit_mode="human"' "$R/docs/pipeline/pipeline.json" > "$TMP/pj" && mv "$TMP/pj" "$R/docs/pipeline/pipeline.json"
tf "rm a test file" gg "rm pkg/x_test.go"
tf "rm -f a python test" gg "rm -f tests/test_x.py"
tf "mv a test file away" gg "mv pkg/x_test.go pkg/x.go.bak"
tf "truncate a test" gg "truncate -s 0 pkg/x_test.go"
tf "sed -i on a test" gg "sed -i 's/assert/skip/' tests/test_x.py"
tf "sed -i.bak on a test" gg "sed -i.bak 's/a/b/' pkg/x_test.go"
tf "redirect into a test" gg "echo 'package x' > pkg/x_test.go"
tf "append into a test" gg "echo x >> pkg/x_test.go"
tf "redirect without spaces" gg "echo x >pkg/x_test.go"
tf "tee into a test" gg "echo x | tee pkg/x_test.go"
tf "cp over a test" gg "cp /tmp/fake.go pkg/x_test.go"
tf "git rm a test" gg "git rm pkg/x_test.go"
tf "git checkout -- a test" gg "git checkout -- pkg/x_test.go"
tf "git restore a test" gg "git restore pkg/x_test.go"
tf "rm the Makefile" gg "rm Makefile"
tf "redirect into CI config" gg "cat /dev/null > .github/workflows/ci.yml"
tf "sed -i on pipeline.json" gg "sed -i 's/human/agent/' docs/pipeline/pipeline.json"
tf "quoted test path" gg "rm 'pkg/x_test.go'"
t  "reading a test is allowed" gg "cat pkg/x_test.go"
t  "grep in tests is allowed" gg "grep -n assert tests/test_x.py"
t  "sed -n (read) on a test is allowed" gg "sed -n 1,20p pkg/x_test.go"
t  "redirect output elsewhere while reading a test" gg "grep foo pkg/x_test.go > /tmp/out.txt"
t  "rm a source file is allowed" gg "rm pkg/old.go"
role_gg() { SDLC_ROLE="$1" gg "$2"; }
cfg_gg() { SDLC_ALLOW_CONFIG=1 gg "$1"; }
t  "test-writer may rm a test" role_gg test-writer "rm pkg/x_test.go"
t  "SDLC_ALLOW_CONFIG=1 may write config" cfg_gg "echo x > Makefile"

group "guard-paths.sh"
fp() { printf '{"tool_input":{"file_path":"%s"}}' "$R/$1"; }
t  "tests-readonly denies Go test"      denies guard-paths.sh "$(fp pkg/x_test.go)" tests-readonly
t  "tests-readonly denies Python test"  denies guard-paths.sh "$(fp tests/test_x.py)" tests-readonly
t  "tests-readonly denies JS test"      denies guard-paths.sh "$(fp src/x.test.ts)" tests-readonly
t  "tests-readonly denies __tests__"    denies guard-paths.sh "$(fp src/__tests__/x.js)" tests-readonly
t  "tests-readonly denies Makefile"     denies guard-paths.sh "$(fp Makefile)" tests-readonly
t  "tests-readonly denies CI config"    denies guard-paths.sh "$(fp .github/workflows/ci.yml)" tests-readonly
t  "tests-readonly denies pipeline.json" denies guard-paths.sh "$(fp docs/pipeline/pipeline.json)" tests-readonly
t  "tests-readonly allows source"       allows guard-paths.sh "$(fp pkg/x.go)" tests-readonly
t  "tests-readonly allows feature docs" allows guard-paths.sh "$(fp docs/features/s/fix-notes.md)" tests-readonly
t  "tests-only denies source"           denies guard-paths.sh "$(fp pkg/x.go)" tests-only
t  "tests-only allows test"             allows guard-paths.sh "$(fp pkg/x_test.go)" tests-only
t  "tests-only allows docs"             allows guard-paths.sh "$(fp docs/features/s/tasks.md)" tests-only
t  "docs-only denies source"            denies guard-paths.sh "$(fp pkg/x.go)" docs-only
t  "docs-only denies test"              denies guard-paths.sh "$(fp pkg/x_test.go)" docs-only
t  "docs-only allows docs"              allows guard-paths.sh "$(fp docs/features/s/review-log.md)" docs-only
role_denies() { SDLC_ROLE="$1" denies "${@:2}"; }
t  "SDLC_ROLE=test-writer overrides mode"   role_denies test-writer guard-paths.sh "$(fp pkg/x.go)" tests-readonly
t  "SDLC_ROLE=code-reviewer overrides mode" role_denies code-reviewer guard-paths.sh "$(fp pkg/x.go)" tests-readonly
patch_json=$(jq -n --arg p $'*** Begin Patch\n*** Update File: pkg/x_test.go\n@@\n-a\n+b\n*** End Patch' '{tool_input:{input:$p}}')
t  "Codex apply_patch paths are read"   denies guard-paths.sh "$patch_json" tests-readonly
t  "empty input allowed"                allows guard-paths.sh '{}' tests-readonly
t  "traversal to a test file"           denies guard-paths.sh "$(fp ../other/pkg/x_test.go)" tests-readonly
t  "dot-slash prefix"                   denies guard-paths.sh "$(fp ./pkg/x_test.go)" tests-readonly
t  "absolute path outside repo, docs-only" denies guard-paths.sh '{"tool_input":{"file_path":"/etc/hosts"}}' docs-only
t  "absolute path outside repo, tests-only" denies guard-paths.sh '{"tool_input":{"file_path":"/tmp/x.go"}}' tests-only
t  "path with spaces"                   denies guard-paths.sh "$(jq -n --arg p "$R/pkg/my test_test.go" '{tool_input:{file_path:$p}}')" tests-readonly
t  "notebook_path key"                  denies guard-paths.sh "$(jq -n --arg p "$R/tests/test_nb.py" '{tool_input:{notebook_path:$p}}')" tests-readonly
t  "generic path key (Gemini write_file)" denies guard-paths.sh "$(jq -n --arg p "$R/pkg/x_test.go" '{tool_input:{path:$p}}')" tests-readonly
t  "apply_patch: Add File into tests"   denies guard-paths.sh "$(jq -n --arg p $'*** Begin Patch\n*** Add File: tests/test_new.py\n+x\n*** End Patch' '{tool_input:{input:$p}}')" tests-readonly
t  "apply_patch: Delete File test"      denies guard-paths.sh "$(jq -n --arg p $'*** Begin Patch\n*** Delete File: pkg/x_test.go\n*** End Patch' '{tool_input:{input:$p}}')" tests-readonly
t  "apply_patch: Move to File over a test" denies guard-paths.sh "$(jq -n --arg p $'*** Begin Patch\n*** Update File: pkg/x.go\n*** Move to File: pkg/x_test.go\n@@\n-a\n+b\n*** End Patch' '{tool_input:{input:$p}}')" tests-readonly
t  "apply_patch: one bad file among good" denies guard-paths.sh "$(jq -n --arg p $'*** Begin Patch\n*** Update File: pkg/a.go\n@@\n-a\n+b\n*** Update File: Makefile\n@@\n-a\n+b\n*** End Patch' '{tool_input:{input:$p}}')" tests-readonly
t  "apply_patch: all source files pass"  allows guard-paths.sh "$(jq -n --arg p $'*** Begin Patch\n*** Update File: pkg/a.go\n@@\n-a\n+b\n*** End Patch' '{tool_input:{input:$p}}')" tests-readonly

group "evidence-gate.sh"
eg() { jq -n --arg a "$1" --arg m "$2" --arg id "eg-$RANDOM$RANDOM" '{agent_type:$a,last_assistant_message:$m,agent_id:$id}' | "$H/evidence-gate.sh" 2>/dev/null; }
blocks() { eg "$@" | grep -q '"decision": *"block"'; }
passes() { [ -z "$(eg "$@")" ]; }
good_rev=$'VERDICT: APPROVE\nTree: 0123456789abcdef0123456789abcdef01234567\n\n## Checks run\nmake test exit code 0\n\n## Evidence\n- pkg/x.go:10'
t  "reviewer with full report passes" passes code-reviewer "$good_rev"
t  "reviewer without VERDICT blocks" blocks code-reviewer $'## Evidence\nmake test exit code 0'
t  "reviewer without Tree blocks" blocks code-reviewer $'VERDICT: APPROVE\n## Evidence\nmake test exit code 0'
t  "reviewer without Evidence blocks" blocks code-reviewer $'VERDICT: APPROVE\nmake test exit code 0'
t  "reviewer without test command blocks" blocks code-reviewer $'VERDICT: APPROVE\n## Evidence\nran tests, exit code 0'
t  "reviewer without exit code blocks" blocks code-reviewer $'VERDICT: APPROVE\n## Evidence\nmake test passed'
t  "qa without QA line blocks" blocks qa-engineer $'## Evidence\nmake test exit code 0'
t  "qa with QA: PASS passes" passes qa-engineer $'QA: PASS\nTree: 0123456789abcdef0123456789abcdef01234567\n## Evidence\nmake test exit code 0'
t  "qa without Tree blocks" blocks qa-engineer $'QA: PASS\n## Evidence\nmake test exit code 0'
t  "test-writer without failure output blocks" blocks test-writer $'## Evidence\nmake test exit code 0'
t  "test-writer with FAIL output passes" passes test-writer $'## Evidence\nmake test exit code 1\n--- FAIL: TestX'
t  "architect needs only Evidence" passes architect $'## Evidence\n- read pkg/x.go:1'
t  "architect without Evidence blocks" blocks architect 'spec written'
t  "unknown agent is ignored" passes some-other-agent 'anything'
jq '.security_cmd="gosec ./..."' "$R/docs/pipeline/pipeline.json" > "$TMP/pj" && mv "$TMP/pj" "$R/docs/pipeline/pipeline.json"
t  "reviewer without security_cmd output blocks when configured" blocks code-reviewer "$good_rev"
t  "reviewer with security_cmd output passes" passes code-reviewer "$good_rev"$'\ngosec ./... exit code 0'
t  "implementer without security_cmd output blocks" blocks implementer $'## Evidence\nmake test exit code 0'
t  "implementer with security_cmd output passes" passes implementer $'## Evidence\nmake test exit code 0\ngosec ./... exit code 0'
t  "test-writer is not asked for security_cmd" passes test-writer $'## Evidence\nmake test exit code 1\n--- FAIL: TestX'
jq '.security_cmd=""' "$R/docs/pipeline/pipeline.json" > "$TMP/pj" && mv "$TMP/pj" "$R/docs/pipeline/pipeline.json"
unnamed() { jq -n --arg m "$1" --arg id "eg-un-$RANDOM" '{last_assistant_message:$m,agent_id:$id}' | "$H/evidence-gate.sh" 2>/dev/null; }
unnamed_blocks() { unnamed $'VERDICT: APPROVE\nno evidence' | grep -q block; }
t  "unnamed agent with VERDICT is treated as a report" unnamed_blocks
cap_id="eg-cap-$RANDOM$RANDOM"
rep() { jq -n --arg id "$cap_id" '{agent_type:"architect",last_assistant_message:"nothing",agent_id:$id}' | "$H/evidence-gate.sh" 2>/dev/null; }
rep_blocks() { rep | grep -q block; }
rep_passes() { [ -z "$(rep)" ]; }
t  "block 1 of 2" rep_blocks
t  "block 2 of 2" rep_blocks
t  "third attempt is let through" rep_passes

group "check-evidence.sh"
cd "$R" || exit 1
TH0=$(cd "$R" && "$E/tree-hash.sh")
printf 'VERDICT: APPROVE\nTree: %s\n## Evidence\nmake test\n| make test | 0 |\n' "$TH0" > "$TMP/review-log.md"
printf 'VERDICT: APPROVE\nTree: %s\n## Evidence\nran tests fine\n' "$TH0" > "$TMP/bad-review-log.md"
printf 'VERDICT: APPROVE\n## Evidence\nmake test\n| make test | 0 |\n' > "$TMP/notree-review-log.md"
printf 'QA: PASS\nTree: %s\n## Evidence\nmake test exit code 0\n' "$TH0" > "$TMP/qa-report.md"
printf 'Tree: %s\n## Evidence\nmake test exit code 0\n' "$TH0" > "$TMP/bad-qa-report.md"
t  "good review-log passes" "$E/check-evidence.sh" "$TMP/review-log.md"
tf "review-log without Tree fails" "$E/check-evidence.sh" "$TMP/notree-review-log.md"
tf "review-log without test cmd fails" "$E/check-evidence.sh" "$TMP/bad-review-log.md"
t  "good qa-report passes" "$E/check-evidence.sh" "$TMP/qa-report.md"
tf "qa-report without QA line fails" "$E/check-evidence.sh" "$TMP/bad-qa-report.md"
tf "missing file fails" "$E/check-evidence.sh" "$TMP/nope.md"

group "check-feature.sh"
F="$R/docs/features/demo"; mkdir -p "$F"
printf '# spec\n' > "$F/spec.md"
sha=$(git hash-object "$F/spec.md")
printf '{"stage":"pr","spec_sha":"%s"}\n' "$sha" > "$F/state.json"
printf -- '- [x] T1 done\n- [x] T2 done\n' > "$F/tasks.md"
TH=$(cd "$R" && "$E/tree-hash.sh")
t  "tree-hash prints a 40-hex hash" bash -c "printf '%s' '$TH' | grep -Eq '^[0-9a-f]{40}$'"
t  "tree-hash ignores docs/features" bash -c "echo note >> '$F/fix-notes.md' && [ \"\$(cd '$R' && '$E/tree-hash.sh')\" = '$TH' ]"
t  "tree-hash changes with source" bash -c "echo x > '$R/pkg_new.go' && [ \"\$(cd '$R' && '$E/tree-hash.sh')\" != '$TH' ] && mv '$R/pkg_new.go' '$TMP/'"
th() { (cd "$R" && "$E/tree-hash.sh"); }
rl() { printf 'VERDICT: %s\nTree: %s\n## Evidence\n%s\n| %s | 0 |\n' "${1:-APPROVE}" "${2:-$(th)}" "${3:-make test}" "${3:-make test}" > "$F/review-log.md"; }
qr() { printf 'QA: PASS\nTree: %s\n## Evidence\n%s exit code 0\n' "${1:-$(th)}" "${2:-make test}" > "$F/qa-report.md"; }
rl; qr
t  "mergeable feature passes" "$E/check-feature.sh" demo
rl APPROVE 0000000000000000000000000000000000000000
tf "review Tree from another tree fails" "$E/check-feature.sh" demo
rl
tf "source changed after QA fails" bash -c "echo x > '$R/pkg_late.go' && '$E/check-feature.sh' demo; rc=\$?; mv '$R/pkg_late.go' '$TMP/'; exit \$rc"
t  "passes again once the tree is restored" "$E/check-feature.sh" demo
setman() { jq --arg p "$(git -C "$R" hash-object "$F/spec.md")" --arg c "$(git -C "$R" hash-object "$R/docs/pipeline/pipeline.json")" '.manifest={spec:$p,pipeline:$c}' "$F/state.json" > "$TMP/st" && cp "$TMP/st" "$F/state.json"; }
setpj() { jq "$1" "$R/docs/pipeline/pipeline.json" > "$TMP/pjx" && cp "$TMP/pjx" "$R/docs/pipeline/pipeline.json"; }
setman
t  "manifest that matches passes" "$E/check-feature.sh" demo
setpj '.max_review_rounds=9'
tf "pipeline.json changed after handoff fails" "$E/check-feature.sh" demo
setpj '.max_review_rounds=3'
t  "manifest matches again after revert" "$E/check-feature.sh" demo
setpj '.test_cmd="true"'; setman; rl APPROVE "$(th)" true; qr "$(th)" true
t  "--run executes test_cmd and passes when it exits 0" "$E/check-feature.sh" demo --run
setpj '.test_cmd="false"'; setman; rl APPROVE "$(th)" false; qr "$(th)" false
t  "without --run a report claiming exit 0 is accepted (testimony)" "$E/check-feature.sh" demo
tf "--run catches the false claim" "$E/check-feature.sh" demo --run
setpj '.test_cmd="true" | .security_cmd="true"'; setman; printf 'VERDICT: APPROVE\nTree: %s\n## Evidence\ntrue\n| true | 0 |\n' "$(th)" > "$F/review-log.md"; qr "$(th)" true
t  "--run with a passing security_cmd passes" "$E/check-feature.sh" demo --run
setpj '.security_cmd="false"'; setman; printf 'VERDICT: APPROVE\nTree: %s\n## Evidence\ntrue\n| true | 0 |\nfalse\n| false | 0 |\n' "$(th)" > "$F/review-log.md"; qr "$(th)" true
tf "--run fails on a failing security_cmd" "$E/check-feature.sh" demo --run
setpj '.security_cmd="gosec ./..."'; setman; printf 'VERDICT: APPROVE\nTree: %s\n## Evidence\ntrue\n| true | 0 |\n' "$(th)" > "$F/review-log.md"; qr "$(th)" true
tf "review-log without the configured security_cmd fails check-evidence" "$E/check-feature.sh" demo
setpj '.test_cmd="make test" | .security_cmd=""'; setman; rl; qr
t  "restored feature passes" "$E/check-feature.sh" demo
printf -- '- [ ] T3 open\n' >> "$F/tasks.md"
tf "unchecked task fails" "$E/check-feature.sh" demo
printf -- '- [x] T1 done\n' > "$F/tasks.md"
printf 'changed\n' >> "$F/spec.md"
tf "spec drift fails" "$E/check-feature.sh" demo
printf '# spec\n' > "$F/spec.md"
rl CHANGES_REQUESTED
tf "non-APPROVE verdict fails" "$E/check-feature.sh" demo
tf "unknown slug fails" "$E/check-feature.sh" nope

group "pre-commit"
ln -sf ../../docs/pipeline/enforcement/pre-commit "$R/.git/hooks/pre-commit"
gc() { git -C "$R" -c user.name=t -c user.email=t@t commit -q -m "$1"; }   # shell function: never call it through env
hgc() { SDLC_HUMAN=1 gc "$1"; }
hgc_tw() { SDLC_HUMAN=1 SDLC_ROLE=test-writer gc "$1"; }
hgc_cfg() { SDLC_HUMAN=1 SDLC_ALLOW_CONFIG=1 gc "$1"; }
echo a > "$R/a.txt"; git -C "$R" add a.txt
tf "agent commit denied (no SDLC_HUMAN)" gc agent
t  "human commit allowed" hgc human
git -C "$R" checkout -q -b develop
echo b > "$R/b.txt"; git -C "$R" add b.txt
tf "commit on protected branch denied" hgc onprotected
git -C "$R" checkout -q feature/scratch
printf '{"stage":"implement","spec_sha":"x"}\n' > "$F/state.json"
echo t > "$R/pkg_test.go"; git -C "$R" add -f pkg_test.go
tf "test edit denied while a feature is in implement" hgc testedit
t  "test edit allowed for SDLC_ROLE=test-writer" hgc_tw testwriter
echo m > "$R/Makefile"; git -C "$R" add Makefile
tf "config edit denied while in implement" hgc cfg
t  "config edit allowed with SDLC_ALLOW_CONFIG=1" hgc_cfg cfgok
mkdir -p "$TMP/gl-find" "$TMP/gl-clean"
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/gl-find/gitleaks"; printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/gl-clean/gitleaks"; chmod +x "$TMP/gl-find/gitleaks" "$TMP/gl-clean/gitleaks"
printf '{"stage":"pr","spec_sha":"x"}\n' > "$F/state.json"
echo s > "$R/s.txt"; git -C "$R" add s.txt
gl_commit() { ( cd "$R" && PATH="$1:$PATH" SDLC_HUMAN=1 "${@:2}" git -c user.name=t -c user.email=t@t commit -q -m secrets ); }
tf "gitleaks finding denies the commit" gl_commit "$TMP/gl-find" env
t  "SDLC_SKIP_SECRETS=1 bypasses once" gl_commit "$TMP/gl-find" env SDLC_SKIP_SECRETS=1
echo s2 > "$R/s2.txt"; git -C "$R" add s2.txt
t  "clean gitleaks run commits" gl_commit "$TMP/gl-clean" env
echo s3 > "$R/s3.txt"; git -C "$R" add s3.txt
t  "no gitleaks on PATH: commit proceeds with a notice" bash -c "cd '$R' && SDLC_HUMAN=1 git -c user.name=t -c user.email=t@t commit -q -m nogl 2>'$TMP/gl.err' && grep -q 'not scanned for secrets' '$TMP/gl.err'"
mkdir -p "$TMP/nojq"; for b in /usr/bin/* /bin/*; do [ "$(basename "$b")" = jq ] || ln -sf "$b" "$TMP/nojq/" 2>/dev/null; done
printf '{"stage":"pr","spec_sha":"x"}\n' > "$F/state.json"
echo c > "$R/c.txt"; git -C "$R" add c.txt
nojq_commit() { ( cd "$R" && PATH="$TMP/nojq" SDLC_HUMAN=1 "$@" git -c user.name=t -c user.email=t@t commit -q -m nojq ); }
tf "pre-commit fails closed without jq" nojq_commit env
t  "SDLC_SKIP_PRECOMMIT=1 lets one commit through without jq" nojq_commit env SDLC_SKIP_PRECOMMIT=1
cd "$HERE" || exit 1

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
