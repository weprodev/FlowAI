---
id: UC-UPD-001
layer: commands
bounded_context: update_command
automated_test: flowai_test_s_upd_001
status: implemented
---

# UC-UPD-001 — flowai update --help exits 0

## Intent
Verify flowai update --help exits 0 and shows usage.

## Preconditions (Given)
- flowai CLI is available

## Action (When)
Run flowai update --help.

## Expected outcome (Then)
- Exits 0 with help text

## Automated checks
Implemented by `flowai_test_s_upd_001` in `tests/suites/update_command.sh`.
