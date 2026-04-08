---
id: UC-CLI-030
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_030
status: implemented
---

# UC-CLI-030 — `fai` short alias matches `flowai`

Users can invoke **`fai`** (Flow + AI) as a shortcut for **`flowai`**. **`bin/fai`** is a **symlink** to **`bin/flowai`** — one script on disk. **`install.sh`** creates **`fai`** under the install prefix and in **`/usr/local/bin`**. The same subcommands apply; **`fai help`** shows a green banner line that mentions the alias.

## Preconditions

- FlowAI repo / install with `bin/fai` and `bin/flowai` executable.

## Steps

1. Run `fai version` — must match `VERSION`.
2. Run `fai help` — exit 0; combined output contains `short for flowai`.

## Expected

- `flowai_test_s_cli_030` in `tests/suites/cli_entrypoint.sh`.
