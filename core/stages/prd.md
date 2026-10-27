# PRD: {slug}

Run the gate check in `docs/pipeline/rules/roles.md` for the `prd` gate before step 3.

1. Create `docs/features/{slug}/` if missing. If `decisions.md` is absent and no idea was given ({args} is empty), stop and tell the user to run `/grill {slug} <idea>` or pass the idea.
2. If `ticket.md` is missing, ask the user for the ticket text or link and write it verbatim from `docs/pipeline/templates/ticket.md` before anything else. Run role `product-manager` with: slug `{slug}`, idea {args}, and instruction to read `decisions.md` if present and `docs/pipeline/templates/prd.md`.
3. When it returns, show the user the requirement list and open questions. Ask them to confirm, edit, or answer questions. Record answers verbatim per `roles.md`. Apply their edits to `prd.md` yourself (minimal edits, keep R-ids stable).
4. Update `state.json`: `stage: "prd"`, append to `history`.
5. Reply: R-id list, and say `/handoff {slug}` is next.
