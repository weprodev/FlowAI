---
id: UC-GRAPH-003
layer: infrastructure
bounded_context: knowledge-graph
automated_test: flowai_test_s_graph_003
status: implemented
---

# UC-GRAPH-003 — flowai_graph_is_enabled reads config.graph.enabled

## Intent

Teams that want to opt-out of the graph can set `config.graph.enabled = false`.
`flowai_graph_is_enabled` must respect this setting.

## Preconditions (Given)

- `.flowai/config.json` contains `{"graph":{"enabled":false}}`

## Action (When)

```bash
flowai_graph_is_enabled
```

## Expected outcome (Then)

- Returns exit code `1` (false - disabled)

## Automated checks

`flowai_test_s_graph_003` in `tests/suites/graph_knowledge.sh`.
