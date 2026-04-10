---
id: UC-GRAPH-015
layer: infrastructure
bounded_context: knowledge-graph
automated_test: flowai_test_s_graph_015
status: implemented
---

# UC-GRAPH-015 — graph.json metadata.spec_count reflects spec file count

## Intent

`metadata.spec_count` enables dashboards and the status command to show spec
coverage at a glance. It must be >= 1 when spec files are present in scan paths.

## Preconditions (Given)

- `specs/my-feature.md` exists

## Action (When)

```bash
flowai_graph_build "true"
```

## Expected outcome (Then)

- `graph.json` `.metadata.spec_count` >= 1

## Automated checks

`flowai_test_s_graph_015` in `tests/suites/graph_knowledge.sh`.
