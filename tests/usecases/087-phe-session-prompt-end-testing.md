---
id: UC-PHE-009
layer: core
bounded_context: phase_execution
automated_test: flowai_test_s_phe_009
status: implemented
---

# UC-PHE-009 — session_prompt_end returns 0 in testing mode

## Intent
Verify flowai_phase_session_prompt_end is a safe no-op during FLOWAI_TESTING=1.

## Preconditions (Given)
- FLOWAI_TESTING=1

## Action (When)
Call flowai_phase_session_prompt_end.

## Expected outcome (Then)
- Returns exit code 0 immediately

## Automated checks
Implemented by `flowai_test_s_phe_009` in `tests/suites/phase_execution.sh`.
