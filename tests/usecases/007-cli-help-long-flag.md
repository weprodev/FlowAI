---
id: UC-CLI-007
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_007
status: implemented
---

# UC-CLI-007 — Show help via `flowai --help` (long option)

## Intent

GNU-style **`--help`** is a universal convention alongside **`-h`**. Both must behave like a successful help request (same as `flowai help`).

## Preconditions (Given)

- Same as UC-CLI-001.

## Action (When)

```bash
flowai --help
```

## Expected outcome (Then)

- **Exit code:** `0`.
- Output includes usage / product name (must contain `FlowAI`).

## Implementation note

`bin/flowai` handles this in the same `case` arm as `-h` and `help` (`-h|--help|help`). This use case exists so **tests** document the contract explicitly (Gemini review gap, 2026).

## Automated checks

`flowai_test_s_cli_007` in `tests/cases/cli_entrypoint.sh`.
