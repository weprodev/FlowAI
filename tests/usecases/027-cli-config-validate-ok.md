---
id: UC-CLI-027
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_027
status: implemented
---

# UC-CLI-027 — `flowai validate` (happy path)

## Intent

After `flowai init`, model-related fields should pass validation against `models-catalog.json`.

## Action (When)

```bash
flowai validate
```

## Expected outcome (Then)

- Exit code `0`.
- Success message referencing the catalog.

## Automated checks

`flowai_test_s_cli_027` in `tests/suites/cli_entrypoint.sh`.
