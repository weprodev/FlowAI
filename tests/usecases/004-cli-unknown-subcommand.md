---
id: UC-CLI-004
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_004
status: implemented
---

# UC-CLI-004 — Reject an unknown subcommand

## Intent

Invalid input must fail fast with a clear error — never silently no-op or mis-route to another command.

## Preconditions (Given)

- Same as UC-CLI-001.

## Action (When)

```bash
flowai not-a-real-command
```

(use any token that is not a defined subcommand)

## Expected outcome (Then)

- **Exit code:** `1`.
- Error output indicates the command is unknown (must include `Unknown command`).

## Automated checks

`flowai_test_s_cli_004` in `tests/cases/cli_entrypoint.sh`.
