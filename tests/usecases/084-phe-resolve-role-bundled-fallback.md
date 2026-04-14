---
id: UC-PHE-006
layer: core
bounded_context: phase_execution
automated_test: flowai_test_s_phe_006
status: implemented
---

# UC-PHE-006 — resolve_role_prompt returns bundled fallback

## Intent
Verify resolve_role_prompt falls back to the bundled role prompt when no overrides exist.

## Preconditions (Given)
- No override files in .flowai/roles/

## Action (When)
Call flowai_phase_resolve_role_prompt for a phase.

## Expected outcome (Then)
- Returns content from bundled roles/ directory

## Automated checks
Implemented by `flowai_test_s_phe_006` in `tests/suites/phase_execution.sh`.
