---
id: UC-114
layer: core
bounded_context: graph_edge_cases
automated_test: flowai_test_s_gredge_004
status: implemented
---

# UC-114 — graph_exists returns 1 with only report

## Intent
Verify flowai_graph_exists returns 1 when only GRAPH_REPORT.md exists but graph.json is missing.

## Preconditions (Given)
- GRAPH_REPORT.md exists, graph.json missing

## Action (When)
Call flowai_graph_exists.

## Expected outcome (Then)
- Returns 1 (incomplete graph)

## Automated checks
Implemented by `flowai_test_s_gredge_004` in `tests/suites/graph_edge_cases.sh`.
