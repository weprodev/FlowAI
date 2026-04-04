---
id: UC-CLI-008
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_008
status: implemented
---

# UC-CLI-008 — Report installed version

## Intent

Users need a **stable way to report which FlowAI build** they run (bug reports, CI logs). The CLI must expose the version from the install’s `VERSION` file.

## Preconditions (Given)

- Same as UC-CLI-001.

## Action (When)

```bash
flowai version
```

and equivalently (top-level flag):

```bash
flowai --version
```

## Expected outcome (Then)

- **Exit code:** `0`.
- Output includes the string `FlowAI` and the same version line as `$FLOWAI_HOME/VERSION` (first line).

## Automated checks

`flowai_test_s_cli_008` in `tests/suites/cli_entrypoint.sh`.
