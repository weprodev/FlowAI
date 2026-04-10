---
id: UC-GRAPH-010
layer: infrastructure
bounded_context: knowledge-graph
automated_test: flowai_test_s_graph_010
status: implemented
---

# UC-GRAPH-010 — Spec files produce graph node type="spec"

## Intent

In the knowledge graph, spec files must appear as `type=spec` nodes (not `file`),
so agents and queries can distinguish authoritative intent from implementation.

## Preconditions (Given)

- A file in `specs/` with spec content

## Action (When)

```bash
_graph_structural_extract_file <spec-file>
```

## Expected outcome (Then)

- Fragment `.nodes[0].type` equals "spec"

## Automated checks

`flowai_test_s_graph_010` in `tests/suites/graph_knowledge.sh`.
