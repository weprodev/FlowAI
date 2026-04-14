---
id: UC-ORCHE-004
layer: orchestration
bounded_context: phase
automated_test: flowai_test_s_orche_004
status: implemented
---

# UC-ORCHE-004 — Phase wait_for returns non-zero on timeout

## Intent
Pipeline must not hang when a signal never arrives.

## Preconditions (Given)
- FLOWAI_PHASE_TIMEOUT_SEC=1.
- No signal file exists.

## Action (When)
Call `flowai_phase_wait_for "never_arrives" "test"`.

## Expected outcome (Then)
- Returns non-zero.

## Automated checks
Implemented by `flowai_test_s_orche_004` in `tests/suites/orchestration_extended.sh`.
