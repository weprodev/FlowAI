---
id: UC-AIR-002
layer: core
bounded_context: ai
automated_test: flowai_test_s_air_002
status: implemented
---

# UC-AIR-002 — resolve_model_for_tool passes valid model through

## Intent
Valid models should pass through unchanged.

## Preconditions (Given)
- "gemini-2.5-pro" is in the catalog for gemini.

## Action (When)
Call `flowai_ai_resolve_model_for_tool "gemini" "gemini-2.5-pro"`.

## Expected outcome (Then)
- Returns "gemini-2.5-pro".

## Automated checks
Implemented by `flowai_test_s_air_002` in `tests/suites/ai_resolution.sh`.
