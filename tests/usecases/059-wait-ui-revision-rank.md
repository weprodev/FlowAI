---
id: UC-WUI-002
layer: core
bounded_context: wait_ui
automated_test: flowai_test_s_wui_002
status: implemented
---

# UC-WUI-002 — Wait UI rank resolution for revision labels

## Intent
Verify revision labels resolve to correct intermediate ranks.

## Preconditions (Given)
- `src/core/wait_ui.sh` is sourced.

## Action (When)
Call `flowai_wait_ui_resolve_rank` with "Plan revision" and "Tasks Revision".

## Expected outcome (Then)
- Returns 11 and 21 respectively.

## Automated checks
Implemented by `flowai_test_s_wui_002` in `tests/suites/wait_ui.sh`.
