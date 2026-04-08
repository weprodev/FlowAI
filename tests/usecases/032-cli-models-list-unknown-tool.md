---
id: UC-CLI-032
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_032
status: implemented
---

# UC-CLI-032 — `flowai models list <unknown-tool>` exits 1

## Intent

Passing an unrecognised tool name to `flowai models list` must fail with a clear
error message, not crash silently. This guards against the `local`-at-scope bug
on the error path and ensures the error message names the invalid argument.

## Preconditions (Given)

- FlowAI is installed.

## Action (When)

```bash
flowai models list __not_a_real_tool__
```

## Expected outcome (Then)

- **Exit code:** `1`.
- Output contains `Unknown` or the tool name.

## Automated checks

`flowai_test_s_cli_032` in `tests/suites/lifecycle_happy.sh`.
