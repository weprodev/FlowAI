---
id: UC-WUI-004
layer: core
bounded_context: wait_ui
automated_test: flowai_test_s_wui_004
status: implemented
---

# UC-WUI-004 — Spin lock acquire and release

## Intent
Verify the mkdir-based spin lock can be acquired and released cleanly.

## Preconditions (Given)
- SIGNALS_DIR points to a temp directory.

## Action (When)
1. Call `_flowai_wait_ui_spin_lock` — should return 0 and create the lock directory.
2. Call `_flowai_wait_ui_spin_unlock` — should remove the lock directory.

## Expected outcome (Then)
- Lock dir exists after acquire, removed after release.

## Automated checks
Implemented by `flowai_test_s_wui_004` in `tests/suites/wait_ui.sh`.
