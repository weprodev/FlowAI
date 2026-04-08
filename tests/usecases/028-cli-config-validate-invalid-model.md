---
id: UC-CLI-028
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_028
status: implemented
---

# UC-CLI-028 — `flowai validate` rejects unknown model ids

## Intent

Manual edits to `.flowai/config.json` must be caught before phases run.

## Preconditions (Given)

- Initialized project with a role `model` set to a string not present in `models-catalog.json` for that role’s `tool`.

## Action (When)

```bash
flowai validate
```

## Expected outcome (Then)

- Exit code non-zero.
- Output mentions invalid model and `flowai models list`.

## Automated checks

`flowai_test_s_cli_028` in `tests/suites/lifecycle_happy.sh`.
