---
id: UC-LOGS-002
layer: commands
bounded_context: logs_command
automated_test: flowai_test_s_logs_002
status: implemented
---

# UC-LOGS-002 — logs.sh requires tmux

## Intent
Verify logs.sh checks for tmux availability via command -v.

## Preconditions (Given)
- logs.sh source file is available

## Action (When)
Grep for tmux check.

## Expected outcome (Then)
- "command -v tmux" is present

## Automated checks
Implemented by `flowai_test_s_logs_002` in `tests/suites/logs_command.sh`.
