# Feature: {slug}

Arguments after the slug: `{args}`. An optional first token `--lite`, `--standard`, or `--full` fixes the tier; the rest is the idea.

Read `docs/features/{slug}/state.json`. If absent, the feature is new. Read `docs/pipeline/pipeline.local.json` for the operator role (see `docs/pipeline/rules/roles.md`).

## Tiers

The pipeline runs at one of three tiers, recorded in `state.json.mode`. The tier is sized from the code the feature touches, which keeps small changes cheap and large ones gated.

| tier | when | stages |
|---|---|---|
| `lite` | blast radius `low` and every R-id sized `S` (one task under `max_task_loc`) | sizing, one-paragraph spec, implement, review, qa |
| `standard` | blast radius `medium`, or any R-id sized `M` or `L` | prd, handoff, implement, review, qa |
| `full` | blast radius `high`, or a data-model change, or the user asks | grill, prd, handoff, implement, review (with the second pass per `pipeline.json`), qa |

A flag on the command fixes the tier. Without a flag, the sizing step below picks it and the user confirms in one line. The tier only goes up on its own: if a later stage finds a data-model change or a `high` blast radius in a `lite` or `standard` run, stop, say why, and recommend the higher tier.

## Sizing (new feature, no flag)

1. Write `docs/features/{slug}/ticket.md` from the template with the idea verbatim. Write a draft `prd.md` with the R-ids the idea states, each with Given/When/Then, each with `source: ticket`. Add nothing the idea does not say.
2. Run role `requirements-analyst` once. It sets blast radius and sizes per R-id.
3. Pick the tier from the table. Tell the user: the tier, the blast radius line with its paths, and the R-ids. Ask them to confirm the tier or name another. Record the answer in `decisions.md` per `roles.md`. Set `state.json.mode`.

## Run

Run the stages for the tier in order, each via its skill, starting from the stage after `state.json.stage`:

| current stage | `lite` | `standard` | `full` |
|---|---|---|---|
| (none) | sizing, then spec | sizing, then `/prd {slug}` | sizing, then `/grill {slug} <idea>` |
| grill | | | `/prd {slug}` |
| prd | | `/handoff {slug}` | `/handoff {slug}` |
| handoff | `/implement {slug}` | `/implement {slug}` | `/implement {slug}` |
| implement | `/review {slug}` | `/review {slug}` | `/review {slug}` |
| review (APPROVE) | `/qa {slug}` | `/qa {slug}` | `/qa {slug}` |
| review (other) | `/review {slug}` | `/review {slug}` | `/review {slug}` |
| qa | `/qa {slug}` (re-run) | same | same |
| needs-human | nothing; show the reason from `review-log.md` or `tasks.md` and stop | same | same |
| pr | nothing; tell the user the PR is waiting on them | same | same |

`lite` spec step: the user confirms the R-ids from sizing (that is the prd gate). Write `spec.md` as one paragraph plus the interface and the test that proves each R-id. Write `tasks.md` with one test task and one implementation task per R-id. Record `spec_sha`, set `stage: "handoff"`, use the branch in `state.json.feature_branch` (create `feat/{slug}` if unset). The analyst's review-log entry from sizing stands as the requirements review.

`standard` skips `grill`; `/prd` reads `ticket.md` and the draft `prd.md` from sizing and asks only what they leave open.

## Rules

- Each stage's human gate is real. When a skill asks the user something, wait for the answer. Do not answer for them. When the gate belongs to another role (see `roles.md`), the stage skill records the handoff and stops; tell the user who is up next.
- On any stage reporting BLOCKED, NOT READY, `needs-human`, or a `Test disputes` entry, stop and show the reason.
- Update `state.json` only through the stage skills.
- One line to the user per stage transition.
