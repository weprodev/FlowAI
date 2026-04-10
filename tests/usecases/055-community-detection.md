---
id: UC-GRAPH-018
layer: infrastructure
bounded_context: knowledge-graph
automated_test: flowai_test_s_graph_018
status: implemented
---

# UC-GRAPH-018 — Community detection annotates nodes with degree and community

## Intent

After community detection runs, every node in the graph must have a `.degree`
(number of edges) and `.community` (god/hub/leaf tier). This classification
drives the God Nodes section in GRAPH_REPORT.md and helps agents orient quickly.

## Preconditions (Given)

- A `graph.json` with 3 nodes and 2 edges connecting node "a" to "b" and "c"

## Action (When)

```bash
_graph_detect_communities
```

## Expected outcome (Then)

- At least one node has `.degree` > 0
- At least one node has `.community` set

## Automated checks

`flowai_test_s_graph_018` in `tests/suites/graph_knowledge.sh`.
