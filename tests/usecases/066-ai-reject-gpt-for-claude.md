---
id: UC-AIR-003
layer: core
bounded_context: ai
automated_test: flowai_test_s_air_003
status: implemented
---

# UC-AIR-003 — resolve_model_for_tool rejects GPT model for Claude

## Intent
OpenAI models must not be used with Claude tool.

## Preconditions (Given)
- Claude tool is configured.

## Action (When)
Call `flowai_ai_resolve_model_for_tool "claude" "gpt-4o"`.

## Expected outcome (Then)
- Does NOT return "gpt-4o". Returns a Claude default instead.

## Automated checks
Implemented by `flowai_test_s_air_003` in `tests/suites/ai_resolution.sh`.
