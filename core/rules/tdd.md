# TDD rules

Enforcement per tool is listed in docs/pipeline/ENFORCEMENT.md (Claude Code: hooks; other tools: git pre-commit and CI checks). These lines explain the intent.

- A task starts with a failing test. Run it and confirm it fails for the intended reason before writing implementation.
- One task at a time from `tasks.md`. Check it off only when its tests pass and the full `test_cmd` passes.
- Test names or docstrings carry the requirement ID: `test_R3_rejects_expired_token`.
- `test-writer` edits test files. `implementer` edits source files. If the implementer thinks a test is wrong, it records the dispute in `tasks.md` under "Test disputes" and stops on that task.
- Write the smallest implementation that makes the test pass, then refactor with the tests green.
- Every bug found in review gets a regression test before the fix.
- Cover the deny/error path as well as the success path for every R-id that has one.
- Commands come from `docs/pipeline/pipeline.json`. Paste real runner output, never a summary.
