---
id: UC-GRAPH-016
layer: application
bounded_context: knowledge-graph
automated_test: flowai_test_s_graph_016
status: implemented
---

# UC-GRAPH-016 — GRAPH_REPORT.md contains Spec Coverage section

## Intent

Agents are directed to read `GRAPH_REPORT.md` first. This file must include a
Spec Coverage section so agents know which specs exist and how many
spec-to-implementation edges were found — enabling SDD-aware reasoning.

## Preconditions (Given)

- At least one spec file in `specs/`

## Action (When)

```bash
flowai_graph_build "true"
```

## Expected outcome (Then)

- `GRAPH_REPORT.md` contains "Spec Coverage"

## Automated checks

`flowai_test_s_graph_016` in `tests/suites/graph_knowledge.sh`.
