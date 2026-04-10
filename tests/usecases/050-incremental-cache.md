---
id: UC-GRAPH-013
layer: infrastructure
bounded_context: knowledge-graph
automated_test: flowai_test_s_graph_013
status: implemented
---

# UC-GRAPH-013 — Incremental build uses SHA256 cache for unchanged files

## Intent

The graph must not reprocess files that haven't changed since the last build.
This makes `flowai graph update` fast on large codebases. The SHA256 cache
is checked per-file; unchanged files reuse their fragment cache.

## Preconditions (Given)

- A project with source files
- First build completed successfully (force=true)

## Action (When)

```bash
flowai_graph_build "false"  # second run — incremental
```

## Expected outcome (Then)

- Build output contains "cached" in the structural pass log line

## Automated checks

`flowai_test_s_graph_013` in `tests/suites/graph_knowledge.sh`.
