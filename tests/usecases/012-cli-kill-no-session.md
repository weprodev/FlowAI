---
id: UC-CLI-012
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_012
status: implemented
---

# UC-CLI-012 — Kill when no session is active

## Intent

**Happy path (no-op):** `flowai kill` must not fail when there is nothing to kill — idempotent teardown for automation and scripts.

## Preconditions (Given)

- `tmux` is installed.
- No FlowAI session exists for the working directory (test uses an empty temp directory).

## Action (When)

```bash
flowai kill
```

## Expected outcome (Then)

- **Exit code:** `0`.
- **stderr** includes a clear idle message (e.g. “No active session found …”).

## Automated checks

`flowai_test_s_cli_012` in `tests/cases/lifecycle_happy.sh`.
