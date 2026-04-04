---
id: UC-CLI-022
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_022
status: implemented
---

# UC-CLI-022 — Commands that need `.flowai/` in an uninitialized directory

## Intent

If **`flowai init`** has **never** been run (no **`.flowai/`** or no **`config.json`**), commands that require project state must **fail fast** with one **clear** message telling the user to run **`flowai init`** — not vague “file not found” noise.

## Preconditions (Given)

- A writable directory with **no** `.flowai/` (or no `config.json`).

## Action (When)

```bash
flowai start --headless
```

and:

```bash
flowai run plan
```

(from that directory)

## Expected outcome (Then)

- **Exit code:** `1`.
- **stderr** / combined output contains **“Not a FlowAI project here”** and **`flowai init`**.

## Automated checks

`flowai_test_s_cli_022` in `tests/cases/lifecycle_happy.sh`.
