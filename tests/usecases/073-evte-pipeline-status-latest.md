---
id: UC-EVTE-005
layer: core
bounded_context: eventlog
automated_test: flowai_test_s_evte_005
status: implemented
---

# UC-EVTE-005 — Pipeline status shows latest event per phase

## Intent
When multiple events exist for the same phase, pipeline_status returns the latest.

## Preconditions (Given)
- Events: spec:started, spec:approved, spec:phase_complete.

## Action (When)
Call `flowai_event_pipeline_status`.

## Expected outcome (Then)
- spec field shows "phase_complete" (latest wins).

## Automated checks
Implemented by `flowai_test_s_evte_005` in `tests/suites/event_log_edge.sh`.
