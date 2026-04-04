---
id: UC-CLI-018
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_018
status: implemented
---

# UC-CLI-018 — Reject invalid `.flowai/config.json`

## Intent

If **`config.json`** exists but is **not valid JSON**, commands that depend on it must **fail fast** with a **clear** error — not undefined behaviour or silent defaults.

## Preconditions (Given)

- `jq` is installed.
- `.flowai/` exists with a **`config.json`** file that is syntactically invalid JSON.

## Action (When)

```bash
flowai init
```

(when re-run in an already-initialized tree), or:

```bash
flowai start --headless
```

## Expected outcome (Then)

- **Exit code:** non-zero (`1`).
- Output mentions **Invalid JSON** and points at **`config.json`**.

## Automated checks

`flowai_test_s_cli_018` in `tests/cases/lifecycle_happy.sh`.
