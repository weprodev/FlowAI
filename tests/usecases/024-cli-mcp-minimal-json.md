---
id: UC-CLI-024
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_024
status: implemented
---

# UC-CLI-024 — `flowai mcp list` seeds minimal `mcp.json`

## Intent

The runtime MCP file consumed by Claude `--mcp-config` should contain only `command` and `args` per server, seeded from `.flowai/config.json` on first use.

## Preconditions (Given)

- `jq` is installed.
- A project initialized with `flowai init` (default `mcp.servers` in config).

## Action (When)

```bash
flowai mcp list
```

## Expected outcome (Then)

- `.flowai/mcp.json` exists.
- `mcpServers.context7` has `command` and `args`.
- Extra metadata such as `description` is not required in the runtime file (minimal shape).

## Automated checks

`flowai_test_s_cli_024` in `tests/suites/lifecycle_happy.sh`.
