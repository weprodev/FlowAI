---
id: UC-095
layer: core
bounded_context: master_orchestration
automated_test: flowai_test_s_mstr_007
status: implemented
---

# UC-095 — rejection context written to signals

## Intent
Verify rejection context is written to signals/tasks.rejection_context.

## Preconditions (Given)
- master.sh exists

## Action (When)
Grep for rejection_context.

## Expected outcome (Then)
- Signal file write is present

## Automated checks
Implemented by `flowai_test_s_mstr_007` in `tests/suites/master_orchestration.sh`.
