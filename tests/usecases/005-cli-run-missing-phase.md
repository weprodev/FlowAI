---
id: UC-CLI-005
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_005
status: implemented
---

# UC-CLI-005 — `flowai run` without a phase argument

## Intent

`run` requires a phase name; omitting it must produce a guided error, not undefined behaviour.

## Preconditions (Given)

- Same as UC-CLI-001.

## Action (When)

```bash
flowai run
```

(no phase name after `run`)

## Expected outcome (Then)

- **Exit code:** `1`.
- Output explains that a phase is required (must include `Usage: flowai run`).

## Automated checks

`flowai_test_s_cli_005` in `tests/cases/cli_entrypoint.sh`.
