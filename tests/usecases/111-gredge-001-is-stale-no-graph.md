---
id: UC-111
layer: core
bounded_context: graph_edge_cases
automated_test: flowai_test_s_gredge_001
status: implemented
---

# UC-111 — is_stale returns 0 when no graph.json

## Intent
Verify flowai_graph_is_stale returns 0 (stale) when graph.json does not exist.

## Preconditions (Given)
- No graph.json in wiki directory

## Action (When)
Call flowai_graph_is_stale.

## Expected outcome (Then)
- Returns 0 indicating staleness

## Automated checks
Implemented by `flowai_test_s_gredge_001` in `tests/suites/graph_edge_cases.sh`.
