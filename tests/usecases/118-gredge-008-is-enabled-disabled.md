---
id: UC-118
layer: core
bounded_context: graph_edge_cases
automated_test: flowai_test_s_gredge_008
status: implemented
---

# UC-118 — is_enabled returns 1 when config disabled

## Intent
Verify flowai_graph_is_enabled returns 1 when config has graph.enabled=false.

## Preconditions (Given)
- config.json with graph.enabled=false

## Action (When)
Call flowai_graph_is_enabled.

## Expected outcome (Then)
- Returns 1 (disabled)

## Automated checks
Implemented by `flowai_test_s_gredge_008` in `tests/suites/graph_edge_cases.sh`.
