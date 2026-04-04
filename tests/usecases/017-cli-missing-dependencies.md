---
id: UC-CLI-017
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_017
status: implemented
---

# UC-CLI-017 — Clear errors when core CLI dependencies are missing

## Intent

If **`jq`**, **`tmux`**, or **`gum`** (for interactive `start`) cannot be resolved on **`PATH`**, the CLI must **fail fast** with a **clear, branded** message — not a silent failure or shell traceback.

## Preconditions (Given)

- A writable directory; for the **`gum`** case, `flowai init` has already succeeded so `start` reaches the gum check.

## Action (When)

- **`flowai init`** with `PATH` that does not expose `jq`.
- **`flowai status`** with `PATH` that does not expose `tmux`.
- **`flowai start`** (interactive, not `--headless`) with `PATH` that still exposes `jq` and `tmux` but **not** `gum`.

## Expected outcome (Then)

- **Exit codes:** non-zero where dependencies are required (`1`).
- Output includes the documented **`log_error`** substrings (e.g. `jq is required`, `tmux is not installed`, `gum is required`).

## Implementation note

- **`jq` / `tmux`:** `PATH` is set to a tiny fake `bin` directory containing only a **`bash`** symlink (`flowai_test_mktemp_fake_bash_only_root` in `tests/lib/harness.sh`), so `command -v jq` / `tmux` fail inside the real scripts.
- **`gum`:** After a real `init`, `PATH` is `fake_bin:dirname(jq):dirname(tmux)` so `gum` is **absent** unless it shares an install directory with `jq` or `tmux` (then the gum subtest is skipped with a clear message).

## Automated checks

`flowai_test_s_cli_017` in `tests/suites/lifecycle_happy.sh`.
