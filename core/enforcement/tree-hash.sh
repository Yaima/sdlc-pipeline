#!/usr/bin/env bash
# Prints a content hash of the working tree: tracked and untracked files, .gitignore respected, committed or not.
# Excludes the feature docs and pipeline logs that stages write, so a review's hash still matches after the
# review-log is saved and after the human commits the same content. Same content, same hash, on any machine.
# Usage: tree-hash.sh            (from anywhere inside the repo)
set -u
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "tree-hash: not a git repo" >&2; exit 1; }
CFG="$ROOT/docs/pipeline/pipeline.json"; DOCS="docs/features"
[ -f "$CFG" ] && command -v jq >/dev/null 2>&1 && DOCS=$(jq -r '.docs_dir // "docs/features"' "$CFG")
IDX=$(mktemp); rm -f "$IDX"; trap 'rm -f "$IDX"' EXIT
cd "$ROOT" || exit 1
GIT_INDEX_FILE="$IDX" git add -A -- . ":(exclude)$DOCS" ":(exclude)docs/pipeline/agent-runs.log" ":(exclude)docs/pipeline/RULE-CANDIDATES.md" >/dev/null 2>&1 || exit 1
GIT_INDEX_FILE="$IDX" git write-tree
