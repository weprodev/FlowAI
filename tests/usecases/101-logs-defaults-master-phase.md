---
id: UC-LOGS-003
layer: commands
bounded_context: logs_command
automated_test: flowai_test_s_logs_003
status: implemented
---

# UC-LOGS-003 — logs.sh defaults to master phase

## Intent
Verify logs.sh defaults to "master" phase when no argument is given.

## Preconditions (Given)
- logs.sh source file is available

## Action (When)
Grep for default assignment.

## Expected outcome (Then)
- phase="${1:-master}" is present

## Automated checks
Implemented by `flowai_test_s_logs_003` in `tests/suites/logs_command.sh`.
