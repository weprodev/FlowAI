---
id: UC-GRAPH-009
layer: infrastructure
bounded_context: knowledge-graph
automated_test: flowai_test_s_graph_009
status: implemented
---

# UC-GRAPH-009 — Spec metadata extraction finds acceptance criteria

## Intent

Given/When/Then and Acceptance Criteria headings in spec documents are the most
valuable SDD knowledge. Extracting them allows agents to validate implementation
against the spec's stated criteria.

## Preconditions (Given)

- Spec file with Given/When/Then headings (3+ items)

## Action (When)

```bash
_graph_extract_spec_meta <file>
```

## Expected outcome (Then)

- `.criteria` array has length >= 3

## Automated checks

`flowai_test_s_graph_009` in `tests/suites/graph_knowledge.sh`.
