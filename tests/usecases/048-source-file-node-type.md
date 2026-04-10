---
id: UC-GRAPH-011
layer: infrastructure
bounded_context: knowledge-graph
automated_test: flowai_test_s_graph_011
status: implemented
---

# UC-GRAPH-011 — Source .sh files produce graph node type="file"

## Intent

Regular shell scripts must produce `type=file` nodes in the graph to distinguish
them from spec nodes. This ensures the trust hierarchy is correct.

## Preconditions (Given)

- A `.sh` file in `src/`

## Action (When)

```bash
_graph_structural_extract_file <sh-file>
```

## Expected outcome (Then)

- Fragment `.nodes[0].type` equals "file"

## Automated checks

`flowai_test_s_graph_011` in `tests/suites/graph_knowledge.sh`.
