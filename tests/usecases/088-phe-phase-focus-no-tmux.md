---
id: UC-PHE-010
layer: core
bounded_context: phase_execution
automated_test: flowai_test_s_phe_010
status: implemented
---

# UC-PHE-010 — phase_focus is no-op without tmux

## Intent
Verify flowai_phase_focus returns 0 when tmux is not available.

## Preconditions (Given)
- tmux not on PATH

## Action (When)
Call flowai_phase_focus.

## Expected outcome (Then)
- Returns 0 without error

## Automated checks
Implemented by `flowai_test_s_phe_010` in `tests/suites/phase_execution.sh`.
