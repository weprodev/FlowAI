---
id: UC-GRAPH-002
layer: infrastructure
bounded_context: knowledge-graph
automated_test: flowai_test_s_graph_002
status: implemented
---

# UC-GRAPH-002 — flowai_graph_exists returns true when graph artifacts present

## Intent

After a successful build, `flowai_graph_exists` returns true so that agents know
the knowledge graph is available for navigation.

## Preconditions (Given)

- `.flowai/wiki/GRAPH_REPORT.md` exists
- `.flowai/wiki/graph.json` exists and contains valid JSON

## Action (When)

```bash
flowai_graph_exists
```

## Expected outcome (Then)

- Returns exit code `0` (true)

## Automated checks

`flowai_test_s_graph_002` in `tests/suites/graph_knowledge.sh`.
