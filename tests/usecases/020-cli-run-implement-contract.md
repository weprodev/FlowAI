---
id: UC-CLI-020
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_020
status: implemented
---

# UC-CLI-020 — `flowai run implement` contract (no AI)

## Intent

Same pattern as **UC-CLI-013** (`plan`): the **implement** phase script must resolve **upstream** (`tasks.ready`) and a **feature** directory before invoking an agent. **`FLOWAI_TEST_SKIP_AI=1`** exits **0** at the contract boundary for CI.

## Preconditions (Given)

- `jq` is installed.
- `flowai init`, `specs/<feature>/` with minimal files, and `.flowai/signals/tasks.ready`.

## Action (When)

```bash
FLOWAI_TEST_SKIP_AI=1 flowai run implement
```

## Expected outcome (Then)

- **Exit code:** `0`.
- Output mentions the **contract test** skip path.

## Automated checks

`flowai_test_s_cli_020` in `tests/suites/lifecycle_happy.sh`.
