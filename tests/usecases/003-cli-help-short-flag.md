---
id: UC-CLI-003
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_003
status: implemented
---

# UC-CLI-003 — Show help via `flowai -h`

## Intent

Short `-h` is a universal convention; behaviour must match `help` semantically (successful help display).

## Preconditions (Given)

- Same as UC-CLI-001.

## Action (When)

```bash
flowai -h
```

## Expected outcome (Then)

- **Exit code:** `0`.
- Output includes product/help content (must contain `FlowAI`).

## Automated checks

`flowai_test_s_cli_003` in `tests/suites/cli_entrypoint.sh`.
