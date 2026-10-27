# Start

1. Read `docs/pipeline/pipeline.local.json`. If missing, ask for a name and role (`solo`, `product`, `engineer`, `qa`, `reviewer`, or a list), write the file, and continue. See `docs/pipeline/rules/roles.md`.
2. Read every `docs/features/*/state.json`. Build two lists:
   - **Waiting on you**: features with a `handoffs[]` entry whose `to_role` matches the operator's role, or whose current stage's gate is owned by the role (per `roles.md`).
   - **In progress elsewhere**: everything else, one line each: slug, stage, round, last verdict.
3. If `{slug}` is given, skip to that feature.
4. Show "Waiting on you" first. For each, the pending question and the command that resumes it (`/prd`, `/handoff`, `/implement`, `/review`, `/qa`).
5. Offer the role's default actions when nothing is waiting:
   - product: `/grill <slug> <idea>`, `/prd <slug>`, `/roadmap <name> <description>`
   - engineer: `/handoff <slug>`, `/implement <slug>`, `/feature <slug> --lite <idea>`
   - qa: `/qa <slug>` for features at stage `review` with `APPROVE`
   - reviewer: `/review <slug>`, and list open PRs from `gh pr list` if `gh` is available
   - solo: all of the above
6. Wait for the user's choice. Run the chosen skill. When resuming a handed-off gate, read the pending `handoffs[]` entry, ask its question, and remove the entry once answered.
