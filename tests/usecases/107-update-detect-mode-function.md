---
id: UC-UPD-003
layer: commands
bounded_context: update_command
automated_test: flowai_test_s_upd_003
status: implemented
---

# UC-UPD-003 — _update_detect_mode function exists

## Intent
Verify update.sh defines _update_detect_mode for install method detection.

## Preconditions (Given)
- update.sh source file is available

## Action (When)
Grep for function definition.

## Expected outcome (Then)
- Function _update_detect_mode is defined

## Automated checks
Implemented by `flowai_test_s_upd_003` in `tests/suites/update_command.sh`.
