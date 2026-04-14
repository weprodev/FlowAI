---
id: UC-115
layer: core
bounded_context: graph_edge_cases
automated_test: flowai_test_s_gredge_005
status: implemented
---

# UC-115 — context_block empty when no graph

## Intent
Verify flowai_graph_context_block returns empty output when graph does not exist.

## Preconditions (Given)
- No graph artifacts

## Action (When)
Call flowai_graph_context_block.

## Expected outcome (Then)
- Output is empty

## Automated checks
Implemented by `flowai_test_s_gredge_005` in `tests/suites/graph_edge_cases.sh`.
