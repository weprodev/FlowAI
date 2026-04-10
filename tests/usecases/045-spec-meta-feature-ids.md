---
id: UC-GRAPH-008
layer: infrastructure
bounded_context: knowledge-graph
automated_test: flowai_test_s_graph_008
status: implemented
---

# UC-GRAPH-008 — Spec metadata extraction finds feature IDs

## Intent

Feature IDs like `UC-AUTH-001`, `FEAT-123`, `REQ-456` embedded in spec documents
must be extracted so agents can answer "show me all specs with UC-AUTH coverage".

## Preconditions (Given)

- Spec file containing "UC-AUTH-001" and "FEAT-123"

## Action (When)

```bash
_graph_extract_spec_meta <file>
```

## Expected outcome (Then)

- `.feature_ids` array includes "UC-AUTH-001" and "FEAT-123"

## Automated checks

`flowai_test_s_graph_008` in `tests/suites/graph_knowledge.sh`.
