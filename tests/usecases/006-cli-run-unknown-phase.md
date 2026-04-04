---
id: UC-CLI-006
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_006
status: implemented
---

# UC-CLI-006 — `flowai run` with a non-existent phase

## Intent

Typos or unsupported phase names must be rejected explicitly before any heavy work (no partial runs).

## Preconditions (Given)

- Same as UC-CLI-001.

## Action (When)

```bash
flowai run definitely-not-a-phase-xyz
```

## Expected outcome (Then)

- **Exit code:** `1`.
- Error indicates the phase is unknown (must include `Unknown phase`).

## Automated checks

`flowai_test_s_cli_006` in `tests/cases/cli_entrypoint.sh`.
