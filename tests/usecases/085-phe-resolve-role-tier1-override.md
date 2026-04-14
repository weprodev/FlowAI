---
id: UC-PHE-007
layer: core
bounded_context: phase_execution
automated_test: flowai_test_s_phe_007
status: implemented
---

# UC-PHE-007 — resolve_role_prompt tier 1 phase-level override wins

## Intent
Verify tier 1 (phase-level file drop) takes priority over bundled roles.

## Preconditions (Given)
- .flowai/roles/{phase}.md exists with custom content

## Action (When)
Call flowai_phase_resolve_role_prompt.

## Expected outcome (Then)
- Returns the phase-level override content

## Automated checks
Implemented by `flowai_test_s_phe_007` in `tests/suites/phase_execution.sh`.
