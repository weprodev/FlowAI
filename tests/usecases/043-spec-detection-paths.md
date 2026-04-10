---
id: UC-GRAPH-006
layer: infrastructure
bounded_context: knowledge-graph
automated_test: flowai_test_s_graph_006
status: implemented
---

# UC-GRAPH-006 — Spec detection identifies spec files by path and name

## Intent

Spec files live in `specs/`, `.specify/`, or follow naming conventions like
`*.spec.md`, `requirements*.md`, `acceptance*.md`. The detector must reliably
classify these to give them elevated trust in the knowledge graph.

## Preconditions (Given)

- Files at: `specs/my-feature.md`, `.specify/setup.json`, `requirements.md`, `acceptance-tests.md`

## Action (When)

```bash
_graph_is_spec_file <file>
```

## Expected outcome (Then)

- All four files return exit code `0` (is spec)

## Automated checks

`flowai_test_s_graph_006` in `tests/suites/graph_knowledge.sh`.
