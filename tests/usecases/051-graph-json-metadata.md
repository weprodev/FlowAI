---
id: UC-GRAPH-014
layer: infrastructure
bounded_context: knowledge-graph
automated_test: flowai_test_s_graph_014
status: implemented
---

# UC-GRAPH-014 — flowai_graph_build produces valid graph.json with metadata

## Intent

After a full build, `graph.json` must be valid JSON and contain the required
fields: `metadata.built_at`, `nodes` (array), `edges` (array). This is the
contract that all downstream consumers (agents, queries, status) rely on.

## Preconditions (Given)

- A FlowAI project with at least one source file

## Action (When)

```bash
flowai_graph_build "true"
```

## Expected outcome (Then)

- `.flowai/wiki/graph.json` exists and is valid JSON
- `.metadata.built_at` is present
- `.nodes` is an array
- `.edges` is an array

## Automated checks

`flowai_test_s_graph_014` in `tests/suites/graph_knowledge.sh`.
