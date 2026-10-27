# Operator roles and gate ownership

The pipeline has human gates. Each gate has an owner role. The person at the keyboard declares their role once in `docs/pipeline/pipeline.local.json` (gitignored; see `docs/pipeline/templates/pipeline.local.json`). Agents never infer the role; if the file is missing, the role is `solo`.

```json
{ "name": "Sam", "role": "engineer" }
```

Roles: `solo` (owns every gate), `product`, `engineer`, `qa`, `reviewer`. A person may list several: `"role": ["engineer", "reviewer"]`.

## Gate ownership

| Gate | What the human confirms | Owner role(s) | Set by skill |
|---|---|---|---|
| prd | requirement list, open questions answered | product | `/prd` |
| handoff | conflicts resolved, task list order, data model | engineer | `/handoff` |
| implement | test disputes, BLOCKED reasons | engineer | `/implement` |
| review | waiving findings at the round cap, second-pass disagreements | reviewer, engineer | `/review` |
| qa | QA defects: fix now or defer | qa | `/qa` |
| pr | merge | reviewer | human, outside the pipeline |

## Gate check (every stage skill runs this before asking a gate question)

1. Read the operator role. `solo` owns every gate; continue.
2. If the operator's role is an owner of this gate, ask the question and wait.
3. Otherwise: write the question to `state.json.handoffs[]` as `{ "gate": "<gate>", "to_role": "<owner>", "question": "...", "asked_by": "<name>", "at": "<iso>" }`, set `state.json.stage` to `"awaiting-<gate>"`, tell the operator who is up next, and stop. Do not answer the gate question on the owner's behalf.
4. When an owner opens a session, the session start check (Claude Code: SessionStart hook; other tools: `/start`) lists pending handoffs for their role. `/start` resumes the right stage; the skill reads the pending handoff, asks the question, then removes the entry.

## What the role changes

- Which gate questions the person is asked, and which are handed off.
- What `/start` offers first (product: grill/prd; engineer: handoff/implement; qa: qa; reviewer: review and PR).
- Nothing about what agents may edit. File permissions come from the role's enforcement (ENFORCEMENT.md), never from the operator role.

## Recording gate answers (every gate, every skill)

When a human answers a gate question, the skill appends to `docs/features/<slug>/decisions.md`:

```
## Gate: <gate> (<ISO timestamp from `date -u`>, by <operator name>)
Question: <the question as asked>
Answer (verbatim): "<the user's words, unedited>"
Interpretation: <one or two lines on what the pipeline will do because of it>
```

The verbatim line is the record. The interpretation is the pipeline's reading and may be wrong; a later reader compares the two. Never paraphrase into the verbatim line. Never write "user confirmed" without the quote.

## Scope changes stop the pipeline

If applying an answer would remove a `must` requirement, downgrade `must` to `should`, or remove a stage input (data model, message contract, migration), the skill does not apply it silently. It sets `state.json.stage: "needs-human"`, writes the proposed change to `decisions.md` under `## Pending scope change`, and asks one yes/no question that names the requirement: "Confirm removing R9 (the close notification to the partner system) from scope?" Only a verbatim yes applies the change, recorded per the section above.
