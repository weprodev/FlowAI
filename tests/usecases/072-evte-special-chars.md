---
id: UC-EVTE-001
layer: core
bounded_context: eventlog
automated_test: flowai_test_s_evte_001
status: implemented
---

# UC-EVTE-001 — Event emit with special characters in detail

## Intent
Event log must handle special characters (quotes, backslashes, newlines) safely.

## Preconditions (Given)
- Empty event log.

## Action (When)
Emit event with detail containing double quotes, backslashes, and newlines.

## Expected outcome (Then)
- JSONL line is valid JSON parseable by jq.

## Automated checks
Implemented by `flowai_test_s_evte_001` in `tests/suites/event_log_edge.sh`.
