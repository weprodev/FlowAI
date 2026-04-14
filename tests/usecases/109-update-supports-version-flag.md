---
id: UC-UPD-005
layer: commands
bounded_context: update_command
automated_test: flowai_test_s_upd_005
status: implemented
---

# UC-UPD-005 — update.sh supports --version flag

## Intent
Verify update.sh supports a --version flag for targeted version updates.

## Preconditions (Given)
- update.sh source file is available

## Action (When)
Grep for --version handling.

## Expected outcome (Then)
- --version flag is parsed and used

## Automated checks
Implemented by `flowai_test_s_upd_005` in `tests/suites/update_command.sh`.
