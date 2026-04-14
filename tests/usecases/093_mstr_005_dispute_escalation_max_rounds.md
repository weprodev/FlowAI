---
id: UC-093
layer: core
bounded_context: master_orchestration
automated_test: flowai_test_s_mstr_005
status: implemented
---

# UC-093 — dispute escalation uses max rounds

## Intent
Verify dispute escalation respects FLOWAI_TASKS_MAX_DISPUTE_ROUNDS.

## Preconditions (Given)
- master.sh exists

## Action (When)
Grep for the variable reference.

## Expected outcome (Then)
- Variable is used in dispute logic

## Automated checks
Implemented by `flowai_test_s_mstr_005` in `tests/suites/master_orchestration.sh`.
