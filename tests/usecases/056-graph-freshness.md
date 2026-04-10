---
id: UC-GRAPH-019
layer: infrastructure
bounded_context: knowledge-graph
automated_test: flowai_test_s_graph_019
status: implemented
---

# UC-GRAPH-019 — flowai_graph_is_stale returns false for freshly built graph

## Intent

A graph built moments ago must not be considered stale. This prevents
unnecessary forced rebuilds that slow down `flowai start`.

## Preconditions (Given)

- `graph.json` with `.metadata.built_at` set to the current UTC timestamp

## Action (When)

```bash
flowai_graph_is_stale
```

## Expected outcome (Then)

- Returns exit code `1` (not stale)

## Automated checks

`flowai_test_s_graph_019` in `tests/suites/graph_knowledge.sh`.
