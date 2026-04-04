---
id: UC-CLI-016
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_016
status: implemented
---

# UC-CLI-016 — `flowai init` is safe to re-run

## Intent

Running **`flowai init`** on a project that already has **`.flowai/config.json`** must **not** clobber user configuration. The implementation must exit successfully and warn that existing config is left in place.

## Preconditions (Given)

- `jq` is installed.
- A directory where `flowai init` has already created `.flowai/config.json`.

## Action (When)

```bash
flowai init
```

(from the same directory, a second time)

## Expected outcome (Then)

- **Exit code:** `0`.
- Output indicates **`.flowai` already exists** / config **left in place** (non-destructive).
- **`config.json` content** is unchanged for keys the user (or test) set before the second run (see automated test for a sentinel field).

## Automated checks

`flowai_test_s_cli_016` in `tests/suites/lifecycle_happy.sh`.
