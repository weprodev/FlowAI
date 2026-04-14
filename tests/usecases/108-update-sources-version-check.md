---
id: UC-UPD-004
layer: commands
bounded_context: update_command
automated_test: flowai_test_s_upd_004
status: implemented
---

# UC-UPD-004 — update.sh sources version-check.sh

## Intent
Verify update.sh sources version-check.sh for semver comparison.

## Preconditions (Given)
- update.sh source file is available

## Action (When)
Grep for source statement.

## Expected outcome (Then)
- version-check.sh is sourced

## Automated checks
Implemented by `flowai_test_s_upd_004` in `tests/suites/update_command.sh`.
