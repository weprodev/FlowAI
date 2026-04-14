---
id: UC-089
layer: core
bounded_context: master_orchestration
automated_test: flowai_test_s_mstr_001
status: implemented
---

# UC-089 — master.sh sources phase.sh and ai.sh

## Intent
Verify master.sh sources both phase.sh and ai.sh for pipeline coordination.

## Preconditions (Given)
- master.sh exists

## Action (When)
Grep for source statements.

## Expected outcome (Then)
- Both phase.sh and ai.sh are sourced

## Automated checks
Implemented by `flowai_test_s_mstr_001` in `tests/suites/master_orchestration.sh`.
