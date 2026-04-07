---
id: UC-CLI-026
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_026
status: implemented
---

# UC-CLI-026 — Catalog validation for model ids

## Intent

When `tool` is `gemini` or `claude`, a model string not present in `models-catalog.json` (FlowAI install / repo root) must be replaced with that tool’s catalog `default_id` (unless `FLOWAI_ALLOW_UNKNOWN_MODEL=1`).

## Preconditions (Given)

- `FLOWAI_HOME` is set.
- A minimal `.flowai/config.json` exists (may be `{}`).

## Action (When)

`flowai_ai_resolve_model_for_tool gemini "not-a-real-model-xyz"` (via sourced `src/core/ai.sh`).

## Expected outcome (Then)

- Resolved model is the Gemini catalog default (e.g. `gemini-2.5-pro`).

## Automated checks

`flowai_test_s_cli_026` in `tests/suites/lifecycle_happy.sh`.
