---
id: UC-117
layer: core
bounded_context: graph_edge_cases
automated_test: flowai_test_s_gredge_007
status: implemented
---

# UC-117 — resolve_paths respects FLOWAI_GRAPH_WIKI_DIR

## Intent
Verify flowai_graph_resolve_paths respects the FLOWAI_GRAPH_WIKI_DIR environment override.

## Preconditions (Given)
- FLOWAI_GRAPH_WIKI_DIR set to custom path

## Action (When)
Call flowai_graph_resolve_paths.

## Expected outcome (Then)
- FLOWAI_GRAPH_WIKI_DIR points to the custom path

## Automated checks
Implemented by `flowai_test_s_gredge_007` in `tests/suites/graph_edge_cases.sh`.
