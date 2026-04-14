---
id: UC-CFGV-002
layer: application
bounded_context: config
automated_test: flowai_test_s_cfgv_002
status: implemented
---

# UC-CFGV-002 — Invalid model for valid tool fails validation

## Intent
`flowai validate` must reject model IDs not in the catalog.

## Preconditions (Given)
- Config: master.tool=gemini, master.model=nonexistent-model-xyz.

## Action (When)
Run `flowai validate`.

## Expected outcome (Then)
- Exit code 1. Output contains "Invalid model".

## Automated checks
Implemented by `flowai_test_s_cfgv_002` in `tests/suites/config_validate.sh`.
