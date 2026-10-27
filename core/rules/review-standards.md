# Review standards

Severity scale, used by code-reviewer and qa-engineer:

| Severity | Meaning | Blocks APPROVE |
|---|---|---|
| blocker | wrong behavior, data loss, security flaw, requirement missing, tests do not run | yes |
| major | requirement partially met, missing error path, untested branch, breaking API change without note | yes |
| minor | readability, naming, duplication, non-idiomatic code | no |
| nit | style, comments, whitespace | no |

Finding format (one per line in a table):

```
| id | severity | confidence | file:line | R-id | problem | reproduction | suggested fix |
```

Rules:

- Every finding cites `file:line` the reviewer opened in this run.
- Every blocker or major carries a reproduction: a failing test run in a scratch worktree, a command with output, or a concrete input traced to a wrong output. Without one it is filed as minor.
- Confidence is 0-100. Blockers and majors under 70 are filed as minors with the reason.
- A suggested fix that the reviewer applied in a scratch worktree without changing any test result downgrades the finding to minor.
- Every blocker or major names the requirement it affects, or `none` if it is a general defect.
- Correctness claims in code comments, commit messages, or notes are not evidence. The reviewer verifies from code and command output.
- The reviewer runs `test_cmd`, `lint_cmd`, `typecheck_cmd`, and `security_cmd` itself and reports exit codes.
- The reviewer builds a coverage table: one row per R-id, columns "spec section", "implementing file", "test". An empty cell is a major.
- Security checks on every diff: input validation at boundaries, authz on new endpoints or actions, secrets in code, unsafe deserialization, injection, path traversal, unbounded resource use. These are the reviewer's reading of the code; `security_cmd` in `pipeline.json` is the deterministic scan, and a repo without one has only the reading.
- The reviewer does not fix code. It reports.
- The reviewer does not soften a verdict because the round count is high. The cap is the orchestrator's problem.
