---
id: UC-LOGS-001
layer: commands
bounded_context: logs_command
automated_test: flowai_test_s_logs_001
status: implemented
---

# UC-LOGS-001 — flowai logs without running session exits 1

## Intent
Verify flowai logs exits 1 with error when no tmux session is running.

## Preconditions (Given)
- No FlowAI tmux session is running

## Action (When)
Run flowai logs.

## Expected outcome (Then)
- Exits 1 with output containing "not running"

## Automated checks
Implemented by `flowai_test_s_logs_001` in `tests/suites/logs_command.sh`.
