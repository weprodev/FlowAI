---
id: UC-LOGS-004
layer: commands
bounded_context: logs_command
automated_test: flowai_test_s_logs_004
status: implemented
---

# UC-LOGS-004 — logs.sh uses less -RXF for display

## Intent
Verify logs.sh uses less with -RXF flags for interactive display.

## Preconditions (Given)
- logs.sh source file is available

## Action (When)
Grep for less invocation.

## Expected outcome (Then)
- "less -RXF" is present

## Automated checks
Implemented by `flowai_test_s_logs_004` in `tests/suites/logs_command.sh`.
