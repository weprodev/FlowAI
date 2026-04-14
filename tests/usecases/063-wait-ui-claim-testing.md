---
id: UC-WUI-006
layer: core
bounded_context: wait_ui
automated_test: flowai_test_s_wui_006
status: implemented
---

# UC-WUI-006 — claim_or_skip returns 1 during FLOWAI_TESTING=1

## Intent
Verify the wait UI claim is disabled in test mode.

## Preconditions (Given)
- FLOWAI_TESTING=1 is set.

## Action (When)
Call `flowai_wait_ui_claim_or_skip 10`.

## Expected outcome (Then)
- Returns 1 (skipped).

## Automated checks
Implemented by `flowai_test_s_wui_006` in `tests/suites/wait_ui.sh`.
