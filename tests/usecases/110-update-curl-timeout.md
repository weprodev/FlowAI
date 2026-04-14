---
id: UC-UPD-006
layer: commands
bounded_context: update_command
automated_test: flowai_test_s_upd_006
status: implemented
---

# UC-UPD-006 — update uses curl with timeout

## Intent
Verify _update_download_and_install uses curl with --max-time for timeout safety.

## Preconditions (Given)
- update.sh source file is available

## Action (When)
Grep for curl timeout flag.

## Expected outcome (Then)
- --max-time is present in curl invocation

## Automated checks
Implemented by `flowai_test_s_upd_006` in `tests/suites/update_command.sh`.
