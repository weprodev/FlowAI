---
id: UC-113
layer: core
bounded_context: graph_edge_cases
automated_test: flowai_test_s_gredge_003
status: implemented
---

# UC-113 — graph_exists returns 1 with only graph.json

## Intent
Verify flowai_graph_exists returns 1 when only graph.json exists but GRAPH_REPORT.md is missing.

## Preconditions (Given)
- graph.json exists, GRAPH_REPORT.md missing

## Action (When)
Call flowai_graph_exists.

## Expected outcome (Then)
- Returns 1 (incomplete graph)

## Automated checks
Implemented by `flowai_test_s_gredge_003` in `tests/suites/graph_edge_cases.sh`.
