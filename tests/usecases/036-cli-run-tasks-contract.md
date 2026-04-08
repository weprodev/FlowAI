---
id: UC-CLI-036
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_036
status: implemented
---

# UC-CLI-036 — `flowai run tasks` contract (no AI)

## Intent

Full **tasks** execution invokes an agent — not suitable for deterministic CI.
This contract validates the tasks phase resolves the feature directory, reads the
upstream `plan.ready` signal, and reaches the "ready to run AI" point.

Tests set **`FLOWAI_TEST_SKIP_AI=1`**, which makes `src/phases/tasks.sh` exit
**0** immediately after validating the fixture.

Without this test, the previously-missing `FLOWAI_TEST_SKIP_AI` guard in
`tasks.sh` would go undetected.

## Preconditions (Given)

- `jq` is installed.
- Project initialized (`flowai init`).
- `specs/<feature>/plan.md` exists.
- `.flowai/signals/plan.ready` exists.
- `FLOWAI_TEST_SKIP_AI=1`.

## Action (When)

```bash
FLOWAI_TEST_SKIP_AI=1 flowai run tasks
```

## Expected outcome (Then)

- **Exit code:** `0`.
- Output mentions the contract / skip path.

## Automated checks

`flowai_test_s_cli_036` in `tests/suites/lifecycle_happy.sh`.
