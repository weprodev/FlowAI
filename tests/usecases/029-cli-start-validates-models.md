---
id: UC-CLI-029
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_029
status: implemented
---

# UC-CLI-029 — `flowai start` enforces model catalog

## Intent

Same rules as `flowai validate`, enforced before tmux starts (non-test runs).

## Preconditions (Given)

- `FLOWAI_TESTING` unset or `0` (production-style run).
- Invalid `master.model` for `master.tool`.

## Action (When)

```bash
flowai start --headless
```

## Expected outcome (Then)

- Exit code `1` before session creation.
- Message indicates model validation failure.

## Automated checks

`flowai_test_s_cli_029` in `tests/suites/lifecycle_happy.sh`.
