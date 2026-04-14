---
id: UC-PHE-005
layer: core
bounded_context: phase_execution
automated_test: flowai_test_s_phe_005
status: implemented
---

# UC-PHE-005 — write_prompt creates launch/ directory if missing

## Intent
Verify write_prompt creates the launch/ subdirectory when it does not exist.

## Preconditions (Given)
- .flowai directory with no launch/ subdirectory

## Action (When)
Call flowai_phase_write_prompt.

## Expected outcome (Then)
- launch/ directory is created and prompt file is written inside it

## Automated checks
Implemented by `flowai_test_s_phe_005` in `tests/suites/phase_execution.sh`.
