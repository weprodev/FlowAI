---
id: UC-UPD-002
layer: commands
bounded_context: update_command
automated_test: flowai_test_s_upd_002
status: implemented
---

# UC-UPD-002 — flowai update --check exits 0

## Intent
Verify flowai update --check tolerates network errors gracefully.

## Preconditions (Given)
- flowai CLI is available

## Action (When)
Run flowai update --check.

## Expected outcome (Then)
- Exits 0 regardless of network availability

## Automated checks
Implemented by `flowai_test_s_upd_002` in `tests/suites/update_command.sh`.
