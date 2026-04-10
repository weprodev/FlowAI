---
id: UC-GRAPH-017
layer: application
bounded_context: knowledge-graph
automated_test: flowai_test_s_graph_017
status: implemented
---

# UC-GRAPH-017 — index.md contains Spec Documents section

## Intent

`index.md` is the content catalog agents consult when looking for specific
knowledge. It must list spec documents separately and before source files,
reflecting their higher trust level in the SDD workflow.

## Preconditions (Given)

- At least one spec file in `specs/`

## Action (When)

```bash
flowai_graph_build "true"
```

## Expected outcome (Then)

- `index.md` contains "Spec Documents"

## Automated checks

`flowai_test_s_graph_017` in `tests/suites/graph_knowledge.sh`.
