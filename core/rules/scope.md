# Scope rules (always on)

The ticket is the authority on scope. Agents implement it; they do not extend it.

## The ticket file

`docs/features/<slug>/ticket.md` holds the request as the human gave it: the ticket text, the requirement document link and the lines that matter, the user's own words from the grill. Agents create it at grill or PRD time by copying, never by summarizing, and never edit it afterwards. When the ticket and any later document disagree, the ticket wins until the human changes the ticket.

## Requirements carry a source

Every R-id in `prd.md` has a `source` column: `ticket` (with the line or phrase it comes from) or `decision <gate timestamp>` (the human said it, verbatim in `decisions.md`). An R-id with no source is invalid: the reviewer blocks on it, the analyst reports it, the architect does not plan it.

## Agents do not add behavior

Behavior means: a flag or config key, a background job or pass, a fallback, a retry or backoff policy, a cap or limit, a rule that fires on its own, an endpoint, a message, a table or column, a switch, a new file that has no counterpart in the ticket. An agent that finds a gap between the ticket and the code reports it as a question marked `[ADDS SCOPE]`, one line, with no default. The human either types the requirement in their own words (then it gets a `decision` source) or says no. "Accept all defaults" never accepts an `[ADDS SCOPE]` item; each one is answered on its own.

Findings on pre-existing code (a reviewer or analyst discovers an old bug) go to `tasks.md` Follow-ups as findings. They become requirements only when the human converts them, with a source.

## Reuse before writing

Before creating a file, type, function, consumer, producer, client, or helper, the author greps for an existing one that does the job and writes one line in the task or spec: `Reused: <path:symbol>` or `Searched: <pattern>; nothing reusable because <one reason>`. A second implementation of something the repo already has (a copied listener, a second producer, a hand-rolled fake beside a mocks package that could hold it) is a review major. Generalizing the existing implementation to take a parameter is the default answer; copying it is not.

## Smallest change

Edit existing functions before adding new ones. Extract a helper only when two tasks need it. Do not move existing code to make room for new code unless the move is the change. A task's source diff is expected to be close to what a person would write by hand for the same ticket; the reviewer names any part that is larger than that.

## Bounded loops

- Requirements analysis: at most `max_analyst_rounds` (`docs/pipeline/pipeline.json`, default 2). After the cap, the analyst lists what blocks, with no defaults and no questions, and the human decides.
- Review: `max_review_rounds` (default 3), then `needs-human`.
- Gate questions: at most five per gate. More than five means the PRD is not ready; say so instead.
