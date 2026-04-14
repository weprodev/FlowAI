---
id: UC-AIR-004
layer: core
bounded_context: ai
automated_test: flowai_test_s_air_004
status: implemented
---

# UC-AIR-004 — resolve_model_for_tool falls back for unknown model

## Intent
Unknown model IDs should fall back to catalog default.

## Preconditions (Given)
- "nonexistent-model-xyz" is not in the catalog.

## Action (When)
Call `flowai_ai_resolve_model_for_tool "gemini" "nonexistent-model-xyz"`.

## Expected outcome (Then)
- Returns catalog default, not "nonexistent-model-xyz".

## Automated checks
Implemented by `flowai_test_s_air_004` in `tests/suites/ai_resolution.sh`.
