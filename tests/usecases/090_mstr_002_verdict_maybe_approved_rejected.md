---
id: UC-090
layer: core
bounded_context: master_orchestration
automated_test: flowai_test_s_mstr_002
status: implemented
---

# UC-090 — verdict MAYBE APPROVED does not match strict regex

## Intent
Verify the strict APPROVED verdict regex rejects "MAYBE APPROVED".

## Preconditions (Given)
- Verdict string "MAYBE APPROVED"

## Action (When)
Test against strict APPROVED regex.

## Expected outcome (Then)
- Does not match

## Automated checks
Implemented by `flowai_test_s_mstr_002` in `tests/suites/master_orchestration.sh`.
