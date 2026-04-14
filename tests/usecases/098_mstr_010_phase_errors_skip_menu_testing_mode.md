---
id: UC-098
layer: core
bounded_context: master_orchestration
automated_test: flowai_test_s_mstr_010
status: implemented
---

# UC-098 — phase errors skip menu in testing mode

## Intent
Verify _master_handle_phase_errors_from_batch skips menu when FLOWAI_TESTING=1.

## Preconditions (Given)
- master.sh exists

## Action (When)
Grep for FLOWAI_TESTING guard.

## Expected outcome (Then)
- Testing guard is present in error handler

## Automated checks
Implemented by `flowai_test_s_mstr_010` in `tests/suites/master_orchestration.sh`.
