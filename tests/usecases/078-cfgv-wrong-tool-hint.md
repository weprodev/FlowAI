---
id: UC-CFGV-005
layer: application
bounded_context: config
automated_test: flowai_test_s_cfgv_005
status: implemented
---

# UC-CFGV-005 — Config with wrong tool for model produces hint

## Intent
When a model belongs to a different tool, validation should suggest the correct tool.

## Preconditions (Given)
- Config: roles.backend-engineer.tool=gemini, model=sonnet (a Claude model).

## Action (When)
Run `flowai validate`.

## Expected outcome (Then)
- Exit code 1. Output contains "Hint" and "claude".

## Automated checks
Implemented by `flowai_test_s_cfgv_005` in `tests/suites/config_validate.sh`.
