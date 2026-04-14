---
id: UC-WUI-003
layer: core
bounded_context: wait_ui
automated_test: flowai_test_s_wui_003
status: implemented
---

# UC-WUI-003 — Wait UI unknown label returns RANK_UNKNOWN

## Intent
Verify unknown labels return the fallback rank value (99).

## Preconditions (Given)
- `src/core/wait_ui.sh` is sourced.

## Action (When)
Call `flowai_wait_ui_resolve_rank "Something random"`.

## Expected outcome (Then)
- Returns 99.

## Automated checks
Implemented by `flowai_test_s_wui_003` in `tests/suites/wait_ui.sh`.
