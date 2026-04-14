---
id: UC-ORCHE-008
layer: orchestration
bounded_context: tools
automated_test: flowai_test_s_orche_008
status: implemented
---

# UC-ORCHE-008 — All tool plugins define required API functions

## Intent
Every tool plugin must implement _run, _print_models, and _run_oneshot.

## Preconditions (Given)
- All tool plugin files are sourced via ai.sh.

## Action (When)
Check `declare -F` for all 12 required functions (4 tools x 3 functions).

## Expected outcome (Then)
- All functions exist. No missing functions.

## Automated checks
Implemented by `flowai_test_s_orche_008` in `tests/suites/orchestration_extended.sh`.
