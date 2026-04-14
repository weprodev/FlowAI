---
id: UC-AIR-006
layer: core
bounded_context: ai
automated_test: flowai_test_s_air_006
status: implemented
---

# UC-AIR-006 — resolve_tool_and_model for pipeline phase

## Intent
Pipeline phases resolve through role config.

## Preconditions (Given)
- Config: pipeline.impl=backend-engineer, roles.backend-engineer.tool=claude.

## Action (When)
Call `flowai_ai_resolve_tool_and_model_for_phase "impl"`.

## Expected outcome (Then)
- Returns "claude:...".

## Automated checks
Implemented by `flowai_test_s_air_006` in `tests/suites/ai_resolution.sh`.
