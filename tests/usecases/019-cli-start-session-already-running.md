---
id: UC-CLI-019
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_019
status: implemented
---

# UC-CLI-019 — `flowai start --headless` when a session already exists

## Intent

If the FlowAI **tmux session is already running** for this repo, a second **`flowai start --headless`** must **not** create a duplicate session or fail mysteriously. It should **exit 0** and explain that the session is **already running** (headless path does not attach).

## Preconditions (Given)

- `jq` and `tmux` are installed.
- `flowai init` completed and a session was created with `flowai start --headless`.

## Action (When)

```bash
flowai start --headless
```

(run again in the same project directory)

## Expected outcome (Then)

- **Exit code:** `0`.
- Output indicates the session is **already running** and (for headless) that we are **not attaching**.

## Automated checks

`flowai_test_s_cli_019` in `tests/suites/lifecycle_happy.sh`.
