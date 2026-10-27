# Grounding: read the code, never recall it

Agents in this repo have no memory between runs. Nothing in a prompt, a summary, or a prior message counts as knowledge of the codebase. Only files on disk and command output count.

## Before any decision

1. Read `docs/features/<slug>/state.json` and the stage inputs listed in `docs/pipeline/PROCESS.md`.
2. Read `docs/pipeline/CODEBASE.md` if it exists. If it is older than the last commit that touched source (`git log -1 --format=%cI -- <src dirs>`), regenerate it with `/codebase-map` first.
3. Locate the real files you will read or change with `Glob` and `Grep`. Open them with `Read`. Quote the lines you are relying on.
4. Run the command, do not predict its output: tests, linters, `git diff`, `git log`, schema dumps.

## Related sources (cross-repo and upstream docs)

`state.json.related[]` lists sibling feature folders in other repos, shared message contracts, and upstream documents (product requirement documents, engineering requirement documents, tickets). The requirements-analyst and architect read every entry that is reachable (a path on disk, a file in a sibling checkout, or an attached export) and report any contradiction between the local PRD and a related source as a conflict, with both citations. A related entry that cannot be reached is listed under "not reachable" in Evidence, never silently skipped. A PRD edit that contradicts a related source needs the scope-change confirmation in `roles.md`.

## Evidence section

Every agent report ends with an `## Evidence` section listing:

- files read, as `path:line-range`
- commands run and their exit codes
- anything the agent looked for and did not find (say "not found", never assume it exists)

A report without an Evidence section is incomplete and the orchestrator sends it back.

## Statements that require a file citation

- "the codebase already has X" → cite the file
- "there is no existing X" → cite the Glob/Grep pattern that returned nothing
- "tests pass" → cite the command and exit code from this run
- "this follows the existing pattern" → cite one existing example

## Forbidden

- Describing a function, table, endpoint, or module without having opened its file in this run.
- Reusing a file list, API shape, or test result from an earlier stage's report instead of re-checking. Earlier reports are leads, not facts.
- Writing a spec section from general framework knowledge when the repo has its own convention. Check the repo first.
