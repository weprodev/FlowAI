---
id: UC-CLI-015
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_015
status: implemented
---

# UC-CLI-015 — Session lifecycle: start → status → kill

## Intent

Verify **stateful** session management: after a headless start, **`status`** must reflect a **running** session (not the idle “not running” message), **`kill`** must tear it down, and **`status`** must again report **idle**. This is the complement to UC-CLI-011/012 (absent session only).

## Preconditions (Given)

- `jq` and `tmux` are installed.
- A disposable project directory with `flowai init` completed.

## Action (When)

In order:

```bash
flowai start --headless
flowai status
flowai kill
flowai status
```

## Expected outcome (Then)

- **Exit codes:** all `0`.
- After start: `tmux has-session` for this repo’s session name.
- First `status`: output indicates an **active** FlowAI session (e.g. header containing `FlowAI session:`), not “not running”.
- `kill`: output indicates the session was **killed** (or equivalent success).
- Second `status`: output indicates **not running** (same contract as UC-CLI-011).
- No stray tmux session remains for that session name.

## Automated checks

`flowai_test_s_cli_015` in `tests/suites/lifecycle_happy.sh`.
