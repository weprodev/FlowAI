---
id: UC-112
layer: core
bounded_context: graph_edge_cases
automated_test: flowai_test_s_gredge_002
status: implemented
---

# UC-112 — is_stale returns 1 for fresh graph

## Intent
Verify flowai_graph_is_stale returns 1 (fresh) for a recently created graph.json.

## Preconditions (Given)
- Freshly created graph.json

## Action (When)
Call flowai_graph_is_stale.

## Expected outcome (Then)
- Returns 1 indicating freshness

## Automated checks
Implemented by `flowai_test_s_gredge_002` in `tests/suites/graph_edge_cases.sh`.
