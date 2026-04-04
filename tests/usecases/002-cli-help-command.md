---
id: UC-CLI-002
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_002
status: implemented
---

# UC-CLI-002 — Show help via `flowai help`

## Intent

Users expect a conventional `help` subcommand for discoverability.

## Preconditions (Given)

- Same as UC-CLI-001 (CLI available, cwd arbitrary).

## Action (When)

```bash
flowai help
```

## Expected outcome (Then)

- **Exit code:** `0`.
- Output includes usage / help text (must contain `Usage`).

## Automated checks

`flowai_test_s_cli_002` in `tests/cases/cli_entrypoint.sh`.
