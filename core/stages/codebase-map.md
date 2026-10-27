# Codebase map

Build `docs/pipeline/CODEBASE.md` from what is on disk. Nothing in it may come from general knowledge of a framework; every line names a file that proves it.

## Gather

- `git ls-files | head -500`, directory tree to depth 3, file counts by extension.
- Manifests: package.json, go.mod, pyproject.toml, Cargo.toml, pom.xml, build.gradle, Makefile, Dockerfile, CI config. Extract the real build, test, lint commands.
- Entry points: main files, server bootstrap, CLI roots, exported package indexes.
- Layers: find the directories that hold handlers/routes, services/domain, persistence/repositories, migrations, config, shared utils. Name one representative file per layer.
- Tests: framework, directory layout, naming pattern, fixture location, how to run one file. Cite two test files.
- Conventions: error handling pattern, logging, dependency injection, validation, auth checks. One cited example each.
- Data: schema files, migration directory, ORM models.
- External boundaries: HTTP clients, queues, third-party SDKs.

## Write

```
# Codebase map (generated <date>, commit <sha>)
## Commands (from <manifest>)
## Layout
## Layers (dir → purpose → example file)
## Entry points
## Tests (framework, layout, run one file, examples)
## Conventions (pattern → example file:line)
## Data model (schema/migrations location)
## External boundaries
## Known gaps (things looked for and not found)
```

Keep it under 200 lines. Then:

- Compare `docs/pipeline/pipeline.json` commands with what the manifests say; if they differ or are empty, propose the exact values to the user (pipeline config is read-only for agents; the user applies them).
- Compare the Repo facts section of `CLAUDE.md` with what you found. List each line that disagrees with the code under `## Known gaps` as "CLAUDE.md says X; disk shows Y (file:line)". Propose the corrected line. When rerun after CLAUDE.md was corrected, drop gap entries that no longer disagree; do not carry stale ones forward.
