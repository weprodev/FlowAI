---
id: UC-CLI-033
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_033
status: implemented
---

# UC-CLI-033 — Catalog-to-plugin OCP contract

## Intent

Every tool listed in `models-catalog.json` **must** have a corresponding plugin
file at `src/tools/<name>.sh` that defines both `flowai_tool_<name>_print_models()`
and `flowai_tool_<name>_run()`.

This is the structural guardian for the Open-Closed Principle: you add a new tool
by creating the plugin file and adding the catalog entry — **no existing file may
need to change**. This test would have caught the `copilot` gap immediately.

## Preconditions (Given)

- `models-catalog.json` exists at `$FLOWAI_HOME`.
- `jq` is installed.

## Action (When)

For each tool key `T` in `models-catalog.json`:

1. Assert `src/tools/T.sh` exists.
2. Assert `flowai_tool_T_print_models()` is defined in that file.
3. Assert `flowai_tool_T_run()` is defined in that file.

## Expected outcome (Then)

- All three assertions pass for every catalog tool.
- **Exit code:** `0`.

## Automated checks

`flowai_test_s_cli_033` in `tests/suites/lifecycle_happy.sh`.
