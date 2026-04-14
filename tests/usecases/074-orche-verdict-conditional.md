---
id: UC-ORCHE-001
layer: orchestration
bounded_context: master
automated_test: flowai_test_s_orche_001
status: implemented
---

# UC-ORCHE-001 — Verdict regex rejects CONDITIONALLY APPROVED

## Intent
Prevent false positive when AI hedges with qualified approval.

## Preconditions (Given)
- The strict APPROVED regex from master.sh.

## Action (When)
Test "VERDICT: CONDITIONALLY APPROVED" against the regex.

## Expected outcome (Then)
- Does NOT match.

## Automated checks
Implemented by `flowai_test_s_orche_001` in `tests/suites/orchestration_extended.sh`.
