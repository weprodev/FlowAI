---
id: UC-PHE-008
layer: core
bounded_context: phase_execution
automated_test: flowai_test_s_phe_008
status: implemented
---

# UC-PHE-008 — resolve_role_prompt tier 2 role-name override wins

## Intent
Verify tier 2 (role-name file drop) wins when no phase-level override exists.

## Preconditions (Given)
- .flowai/roles/{role-name}.md exists

## Action (When)
Call flowai_phase_resolve_role_prompt.

## Expected outcome (Then)
- Returns the role-name override content

## Automated checks
Implemented by `flowai_test_s_phe_008` in `tests/suites/phase_execution.sh`.
