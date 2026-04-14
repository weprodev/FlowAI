---
id: UC-PHE-004
layer: core
bounded_context: phase_execution
automated_test: flowai_test_s_phe_004
status: implemented
---

# UC-PHE-004 — write_prompt creates file with role+directive+boundary

## Intent
Verify flowai_phase_write_prompt produces a prompt file containing role content, directive, and artifact boundary.

## Preconditions (Given)
- Temp .flowai directory with config.json

## Action (When)
Call flowai_phase_write_prompt for a phase.

## Expected outcome (Then)
- Generated prompt file contains role content, directive text, and artifact boundary

## Automated checks
Implemented by `flowai_test_s_phe_004` in `tests/suites/phase_execution.sh`.
