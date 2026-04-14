---
id: UC-097
layer: core
bounded_context: master_orchestration
automated_test: flowai_test_s_mstr_009
status: implemented
---

# UC-097 — post-QA review markers

## Intent
Verify post-QA review uses READY_FOR_HUMAN_SIGNOFF and NEEDS_FOLLOW_UP markers.

## Preconditions (Given)
- master.sh exists

## Action (When)
Grep for both markers.

## Expected outcome (Then)
- Both markers are present

## Automated checks
Implemented by `flowai_test_s_mstr_009` in `tests/suites/master_orchestration.sh`.
