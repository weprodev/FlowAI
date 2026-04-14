---
id: UC-116
layer: core
bounded_context: graph_edge_cases
automated_test: flowai_test_s_gredge_006
status: implemented
---

# UC-116 — log_append creates wiki directory

## Intent
Verify flowai_graph_log_append creates the wiki directory if it does not exist.

## Preconditions (Given)
- Wiki directory does not exist

## Action (When)
Call flowai_graph_log_append with a build entry.

## Expected outcome (Then)
- Wiki directory is created and log file contains the entry

## Automated checks
Implemented by `flowai_test_s_gredge_006` in `tests/suites/graph_edge_cases.sh`.
