---
id: UC-LOGS-006
layer: commands
bounded_context: logs_command
automated_test: flowai_test_s_logs_006
status: implemented
---

# UC-LOGS-006 — logs.sh sources session.sh

## Intent
Verify logs.sh sources session.sh for session name resolution.

## Preconditions (Given)
- logs.sh source file is available

## Action (When)
Grep for source statement.

## Expected outcome (Then)
- "source.*session.sh" is present

## Automated checks
Implemented by `flowai_test_s_logs_006` in `tests/suites/logs_command.sh`.
