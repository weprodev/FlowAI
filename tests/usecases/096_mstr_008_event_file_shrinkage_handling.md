---
id: UC-096
layer: core
bounded_context: master_orchestration
automated_test: flowai_test_s_mstr_008
status: implemented
---

# UC-096 — event file shrinkage handling

## Intent
Verify _master_check_events resets the line counter when the event file shrinks.

## Preconditions (Given)
- master.sh exists

## Action (When)
Grep for shrinkage/reset logic.

## Expected outcome (Then)
- Line counter reset logic is present

## Automated checks
Implemented by `flowai_test_s_mstr_008` in `tests/suites/master_orchestration.sh`.
