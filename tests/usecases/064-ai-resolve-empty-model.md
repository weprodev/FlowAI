---
id: UC-AIR-001
layer: core
bounded_context: ai
automated_test: flowai_test_s_air_001
status: implemented
---

# UC-AIR-001 — resolve_model_for_tool returns catalog default for empty input

## Intent
When no model is specified, the resolver should return the catalog default.

## Preconditions (Given)
- Config exists with master tool set.
- models-catalog.json has defaults.

## Action (When)
Call `flowai_ai_resolve_model_for_tool "gemini" ""`.

## Expected outcome (Then)
- Returns a non-empty model ID from the catalog.

## Automated checks
Implemented by `flowai_test_s_air_001` in `tests/suites/ai_resolution.sh`.
