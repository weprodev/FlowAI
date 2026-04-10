---
id: UC-GRAPH-004
layer: application
bounded_context: knowledge-graph
automated_test: flowai_test_s_graph_004
status: implemented
---

# UC-GRAPH-004 — Context block is empty when no graph exists

## Intent

Agents receive the graph context block in their system prompt. When no graph
exists, the block must be empty so the prompt is not polluted with broken refs.

## Preconditions (Given)

- No graph built (`.flowai/wiki/` empty)

## Action (When)

```bash
flowai_graph_context_block
```

## Expected outcome (Then)

- Returns empty string (no output)

## Automated checks

`flowai_test_s_graph_004` in `tests/suites/graph_knowledge.sh`.
