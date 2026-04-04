---
id: UC-CLI-021
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_021
status: implemented
---

# UC-CLI-021 — `flowai stop` is an alias for `kill`

## Intent

**`flowai stop`** must behave like **`flowai kill`** (same script), for familiarity with common service CLIs.

## Action (When)

```bash
flowai stop
```

## Expected outcome (Then)

Same contract as **UC-CLI-012** when no session exists: exit **0**, clear idle message on stderr.

## Automated checks

`flowai_test_s_cli_021` in `tests/suites/lifecycle_happy.sh`.
