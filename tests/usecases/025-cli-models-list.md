---
id: UC-CLI-025
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_025
status: implemented
---

# UC-CLI-025 — List valid models (`flowai models list`)

## Intent

Users need a single source of truth for model ids accepted by each vendor CLI. `flowai models list` prints the bundled catalog.

## Preconditions (Given)

- FlowAI is installed / `FLOWAI_HOME` points at the repo.

## Action (When)

```bash
flowai models list
```

## Expected outcome (Then)

- Exit code `0`.
- Output mentions both tools and includes at least one known id per tool (e.g. `gemini-2.5-pro`, `sonnet`).

## Automated checks

`flowai_test_s_cli_025` in `tests/suites/cli_entrypoint.sh`.
