---
id: UC-WUI-005
layer: core
bounded_context: wait_ui
automated_test: flowai_test_s_wui_005
status: implemented
---

# UC-WUI-005 — Spin lock timeout when already held

## Intent
Verify spin lock returns non-zero when it cannot acquire the lock.

## Preconditions (Given)
- The spinlock directory already exists (simulating another holder).

## Action (When)
Call `_flowai_wait_ui_spin_lock` (wrapped in timeout to avoid 20s wait).

## Expected outcome (Then)
- Returns non-zero (1 or timeout exit code).

## Automated checks
Implemented by `flowai_test_s_wui_005` in `tests/suites/wait_ui.sh`.
