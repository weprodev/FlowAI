---
id: UC-CLI-031
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_031
status: implemented
---

# UC-CLI-031 — `flowai models list -h` exits 0

## Intent

The `models` command must handle `-h`, `--help`, and `help` without crashing.
This guards against regressions where variables are declared with `local` outside
a function body (a bash error under `set -euo pipefail`).

## Preconditions (Given)

- FlowAI is installed (no project init needed — models list is global).

## Action (When)

```bash
flowai models list -h
flowai models list --help
flowai models list help
```

## Expected outcome (Then)

- **Exit code:** `0`.
- Output contains `Usage:` or similar help text.

## Automated checks

`flowai_test_s_cli_031` in `tests/suites/lifecycle_happy.sh`.
