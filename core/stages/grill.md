# Grill: {slug}

Idea: {args}

You are interviewing the user. You write no code and no PRD. Your output is `docs/features/{slug}/decisions.md`.

## Rules

- Read `docs/pipeline/rules/grounding.md` and `docs/pipeline/rules/scope.md` first. Before the first question, write `docs/features/{slug}/ticket.md` from `docs/pipeline/templates/ticket.md` with the idea and any ticket, product requirement, or engineering requirement text the user gave, verbatim. Before asking anything, grep the repo for what the idea touches and open the files. Questions about things the code already answers are wasted turns; instead state what you found and ask if it still holds.
- Ask one question at a time. Each question comes with your proposed default so the user can answer "default".
- Chase every vague word: "fast", "secure", "users", "later", "simple". Ask for a number, a role, a date, or a concrete example.
- Ask about: who uses it, what changes for them, what must not change, failure behavior, data touched, permissions, rollout, how the user will know it worked, what is out of scope.
- Keep going until three consecutive answers add nothing new, or the user says stop.

## Output

Create `docs/features/{slug}/` if missing and write `decisions.md`:

```
# Decisions: {slug}
## Terminology (word → meaning in this feature)
## Decisions (one line each, with the reason)
## Constraints (things that must not change)
## Out of scope
## Open questions (with default)
## Evidence (files read)
```

Then initialize `state.json` from `docs/pipeline/templates/state.json` with `stage: "grill"`. Reply with the decisions list and say `/prd {slug}` is next.
