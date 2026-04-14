---
id: UC-WUI-001
layer: core
bounded_context: wait_ui
automated_test: flowai_test_s_wui_001
status: implemented
---

# UC-WUI-001 — Wait UI rank resolution for known phases

## Intent
Verify that `flowai_wait_ui_resolve_rank` returns correct rank values for all four pipeline phases.

## Preconditions (Given)
- `src/core/wait_ui.sh` is sourced.

## Action (When)
Call `flowai_wait_ui_resolve_rank` with "Plan Phase", "Tasks Phase", "Implement Phase", "Review Phase".

## Expected outcome (Then)
- Returns 10, 20, 30, 40 respectively.

## Automated checks
Implemented by `flowai_test_s_wui_001` in `tests/suites/wait_ui.sh`.
