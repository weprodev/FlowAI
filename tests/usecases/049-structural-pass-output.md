---
id: UC-GRAPH-012
layer: infrastructure
bounded_context: knowledge-graph
automated_test: flowai_test_s_graph_012
status: implemented
---

# UC-GRAPH-012 — Structural pass creates structural.json with nodes

## Intent

The structural pass must produce a valid `structural.json` with at least as many
nodes as there are files in the scan paths — verifying the JSONL accumulation
pipeline works correctly end-to-end.

## Preconditions (Given)

- `src/` directory with two `.sh` files

## Action (When)

```bash
_graph_run_structural_pass "true"
```

## Expected outcome (Then)

- `.flowai/wiki/cache/structural.json` exists
- `.nodes | length` >= 2

## Automated checks

`flowai_test_s_graph_012` in `tests/suites/graph_knowledge.sh`.
