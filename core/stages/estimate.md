# Estimate: {slug}

Produce or refresh `docs/features/{slug}/estimate.md`: expected effort, worst case with named risks, and a comparison with the ticket's own estimate. Optional at any point after `ticket.md` exists; most useful right after the ticket is filed (to challenge its points) and again after `handoff` (when the task list exists).

## Steps

1. Read `docs/pipeline/rules/grounding.md` and `docs/pipeline/rules/scope.md`. `docs/features/{slug}/ticket.md` must exist; if not, stop and say the ticket text is needed first (`grill` writes it).
2. Run role `estimator` with slug `{slug}`. Pass only the slug. The role reads the feature folder and the repo itself.
3. If `estimate.md` already exists, the role appends a `## Revision (<stage>, <date>)` section with the new figures and what changed since the previous estimate, and leaves the earlier sections in place. Estimates are a record, not a replacement.
4. Append to `state.json.history`: `{"stage": "estimate", "at": <now>, "by": <role from pipeline.local.json>, "result": "expected X–Y h / X–Y d, worst X–Y h / X–Y d"}`. `state.json.stage` is unchanged; estimating is not a pipeline stage.
5. Reply with the role's four lines. If the role listed Blockers, repeat them: they are the human's to route, and nothing in the pipeline proceeds on a broken build.

The estimate adds no scope. An Unknown in `estimate.md` becomes work only when a human answers it in a gate, recorded in `decisions.md`.
