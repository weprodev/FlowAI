---
id: UC-GRAPH-020
layer: infrastructure
bounded_context: knowledge-graph
automated_test: flowai_test_s_graph_020
status: implemented
---

# UC-GRAPH-020 — flowai_graph_log_append writes entries to log.md

## Intent

All graph operations (build, update, ingest, query, lint) are logged to `log.md`
for auditability and incremental history. Agents can query this log to understand
the graph's build history without running a fresh build.

## Preconditions (Given)

- `.flowai/wiki/` directory exists

## Action (When)

```bash
flowai_graph_log_append "build" "nodes=10 edges=20"
flowai_graph_log_append "query" "how does X work?"
```

## Expected outcome (Then)

- `log.md` contains lines with "build" and "query"

## Automated checks

`flowai_test_s_graph_020` in `tests/suites/graph_knowledge.sh`.
