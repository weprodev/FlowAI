---
id: UC-GRAPH-005
layer: application
bounded_context: knowledge-graph
automated_test: flowai_test_s_graph_005
status: implemented
---

# UC-GRAPH-005 — Context block includes node count when graph exists

## Intent

When the graph exists, the context block injected into agent prompts must include
the node count and a recognizable FlowAI header so agents know how to navigate.

## Preconditions (Given)

- `.flowai/wiki/graph.json` with `metadata.node_count = 42`
- `.flowai/wiki/GRAPH_REPORT.md` exists

## Action (When)

```bash
flowai_graph_context_block
```

## Expected outcome (Then)

- Output contains "42 nodes"
- Output contains "FLOWAI KNOWLEDGE GRAPH"

## Automated checks

`flowai_test_s_graph_005` in `tests/suites/graph_knowledge.sh`.
