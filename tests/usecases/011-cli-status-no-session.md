---
id: UC-CLI-011
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_011
status: implemented
---

# UC-CLI-011 — Session status when no tmux session exists

## Intent

**Happy path (idle):** `flowai status` must succeed when no FlowAI tmux session is running for the current repo path — users should get a clear message, not a hard failure.

## Preconditions (Given)

- `tmux` is installed.
- No FlowAI session exists for the working directory (test uses an empty temp directory).

## Action (When)

```bash
flowai status
```

## Expected outcome (Then)

- **Exit code:** `0`.
- Output indicates the session is **not** running (e.g. “not running”).

## Automated checks

`flowai_test_s_cli_011` in `tests/cases/lifecycle_happy.sh`.
