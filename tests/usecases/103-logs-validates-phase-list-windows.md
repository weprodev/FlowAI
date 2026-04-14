---
id: UC-LOGS-005
layer: commands
bounded_context: logs_command
automated_test: flowai_test_s_logs_005
status: implemented
---

# UC-LOGS-005 — logs.sh validates phase via list-windows

## Intent
Verify logs.sh validates the phase name against running tmux windows.

## Preconditions (Given)
- logs.sh source file is available

## Action (When)
Grep for list-windows.

## Expected outcome (Then)
- tmux list-windows is used for validation

## Automated checks
Implemented by `flowai_test_s_logs_005` in `tests/suites/logs_command.sh`.
