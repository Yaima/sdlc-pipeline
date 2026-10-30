# Gates: the local board

A local view of every feature the pipeline is running across your repos: which gates wait on you, where each feature sits, which roles are running, and which rule candidates are pending for retro. It runs on your machine from this checkout. It reads the pipeline's files and writes one file of its own, `board/board.local.json`; it can also run this checkout's `install.sh` into a repo you pick. It never writes a feature's files. Authority stays in the pipeline's files and in CI (`docs/pipeline/ENFORCEMENT.md`).

```
board/
  serve.py                  standard-library server: / and /api/state
  index.html                the page, on board/design
  design/                   tokens, components, preview, contrast check (see design/README.md)
  board.local.example.json  copy to board.local.json and list your repos
```

## Run

```bash
python3 board/serve.py        # http://localhost:7777
```

Then add repos on the Repos screen: type or browse to a git repository, pick an install mode (minimal, full, guards only, or add without installing), and the board writes `board/board.local.json` and runs `install.sh`. Repos under a scan root that already have the pipeline appear on their own; git repos under a root without the pipeline are listed with an "Add and install" button. Each repo row offers Install, Upgrade (when the checkout is newer than the repo's `docs/pipeline/VERSION`), and Remove (from the board only; the repo's files are left alone). The file can also be edited by hand; `board.local.example.json` shows the shape.

`--port`, `--config`, and `--repo PATH` (repeatable) override the file. `--json` prints the state once and exits, which is what the self-test uses.

Needs `python3`, `git`, `bash`, and `jq` on PATH (the tree check calls the pipeline's `tree-hash.sh`). No npm, no build step, no database.

## What it reads, per repo

| File | Used for |
|---|---|
| `docs/features/*/state.json` | slug, tier, stage, rounds, verdict, blast radius, cost, handoffs, history, waived findings |
| `docs/features/*/review-log.md` | last verdict, `Tree:` hash, finding counts by severity from the last round, stopping criterion |
| `docs/features/*/qa-report.md` | `QA:` line and its `Tree:` |
| `docs/features/*/tasks.md` | checked and unchecked tasks, test disputes |
| `docs/pipeline/enforcement/tree-hash.sh` | the current tree hash, compared with the reviewed one (cached 15s) |
| `docs/pipeline/agent-runs.log` | start and stop lines per role; a start without a stop within `stale_minutes` is running |
| `docs/pipeline/RULE-CANDIDATES.md` | pending rule candidates |
| `docs/pipeline/VERSION` | which pipeline version the repo has |

Start lines in `agent-runs.log` need the `SubagentStart` hook that ships with pipeline version 2026.10.29 or later; older installs show finished runs only. A running role is attributed to the feature whose `state.json` changed most recently in that repo, and the board labels that as inferred.

## Screens

- Overview: the waiting band (every gate that needs a person, with the question and the command that resumes it), then repos with one card per feature. The stage track on each card follows the CI status convention: green check passed, teal dot running, amber pause waiting on a person, red cross stopped, grey ring not started.
- Feature: the track, state fields, findings, the tree check, tasks, and recent history. Click a card's slug.
- Live: running roles and the last few finished ones.
- Rules: pending rule candidates across repos.
- Repos: what is configured and what version each has.

## Where it stops

The board's writes are limited to its own config and to running `install.sh`. Write calls are accepted only from the page itself (the server binds to 127.0.0.1 and requires the `X-Gates` header, which a cross-site form cannot send). Nothing on the board triggers a stage, answers a gate, changes a tier, or merges. Those are decisions recorded in the pipeline's files by a person in a session, so the audit trail is the same whether or not a board exists. If actions are ever added, they write the same files in the same format (`decisions.md` per `rules/roles.md`, `state.json` through the stage skills) and merge stays on the server.

## Self-test

`tests/run.sh` runs `serve.py --json` against its scratch repos and checks the API shape: waiting items for handoffs and `needs-human`, the track states, tree match and drift, task counts, and rule candidates.
