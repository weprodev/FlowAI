---
id: UC-AIR-005
layer: core
bounded_context: ai
automated_test: flowai_test_s_air_005
status: implemented
---

# UC-AIR-005 — resolve_tool_and_model for master phase

## Intent
Master phase uses master config directly.

## Preconditions (Given)
- Config: master.tool=gemini, master.model=gemini-2.5-pro.

## Action (When)
Call `flowai_ai_resolve_tool_and_model_for_phase "master"`.

## Expected outcome (Then)
- Returns "gemini:gemini-2.5-pro".

## Automated checks
Implemented by `flowai_test_s_air_005` in `tests/suites/ai_resolution.sh`.
