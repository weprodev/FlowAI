---
id: UC-GRAPH-001
layer: infrastructure
bounded_context: knowledge-graph
automated_test: flowai_test_s_graph_001
status: implemented
---

# UC-GRAPH-001 — flowai_graph_exists returns false when no graph

## Intent

When the knowledge graph has not been built, `flowai_graph_exists` returns false
so that agents and commands can detect the missing graph and prompt the user.

## Preconditions (Given)

- FlowAI project initialized (`.flowai/config.json` exists)
- `.flowai/wiki/GRAPH_REPORT.md` does NOT exist

## Action (When)

```bash
flowai_graph_exists
```

## Expected outcome (Then)

- Returns exit code `1` (false)

## Automated checks

`flowai_test_s_graph_001` in `tests/suites/graph_knowledge.sh`.
