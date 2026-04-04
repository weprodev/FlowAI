---
id: UC-CLI-009
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_009
status: implemented
---

# UC-CLI-009 — Contextual help for `flowai run`

## Intent

Global help lists commands; **`run`** needs its own help so users can discover **phase names** without reading source. Standard convention: `flowai run --help` (and `-h` / `help` as the first argument after `run`).

## Preconditions (Given)

- Same as UC-CLI-001.

## Action (When)

```bash
flowai run --help
```

## Expected outcome (Then)

- **Exit code:** `0`.
- Output describes the `run` subcommand and lists available **phases** (at minimum mentions `phase` / phase names such as `master`, `plan`).

## Automated checks

`flowai_test_s_cli_009` in `tests/suites/cli_entrypoint.sh`.
