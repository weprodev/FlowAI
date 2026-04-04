---
id: UC-CLI-010
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_010
status: implemented
---

# UC-CLI-010 — Initialize a project (`flowai init`)

## Intent

**Happy path:** in a clean directory, `flowai init` creates `.flowai/` (including `config.json`) and `specs/`, and exits successfully. This is the primary onboarding step before `start` / `run`.

## Preconditions (Given)

- `jq` is installed (required by `init`).
- Current directory is writable and does not already contain a conflicting `.flowai` (test uses a temporary directory).

## Action (When)

```bash
flowai init
```

## Expected outcome (Then)

- **Exit code:** `0`.
- `.flowai/config.json` exists.
- `specs/` exists.

## Automated checks

`flowai_test_s_cli_010` in `tests/suites/lifecycle_happy.sh`.
