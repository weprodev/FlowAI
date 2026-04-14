---
id: UC-PHE-001
layer: core
bounded_context: phase_execution
automated_test: flowai_test_s_phe_001
status: implemented
---

# UC-PHE-001 — emit_error creates valid error event

## Intent
Verify flowai_phase_emit_error creates a valid JSON error event in events.jsonl.

## Preconditions (Given)
- Empty events.jsonl

## Action (When)
Call flowai_phase_emit_error with a test phase and message.

## Expected outcome (Then)
- events.jsonl contains valid JSONL with event=error

## Automated checks
Implemented by `flowai_test_s_phe_001` in `tests/suites/phase_execution.sh`.
