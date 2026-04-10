---
id: UC-GRAPH-007
layer: infrastructure
bounded_context: knowledge-graph
automated_test: flowai_test_s_graph_007
status: implemented
---

# UC-GRAPH-007 — Regular source files are not classified as spec files

## Intent

Source files in `src/` and general `docs/` must not be mis-classified as specs,
as that would incorrectly elevate their trust level in the graph.

## Preconditions (Given)

- Files: `src/main.sh`, `docs/README.md`, `src/config.json`

## Action (When)

```bash
_graph_is_spec_file <file>
```

## Expected outcome (Then)

- All three files return exit code `1` (not spec)

## Automated checks

`flowai_test_s_graph_007` in `tests/suites/graph_knowledge.sh`.
