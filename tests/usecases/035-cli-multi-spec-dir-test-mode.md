---
id: UC-CLI-035
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_035
status: implemented
---

# UC-CLI-035 — Multi-spec-dir: test mode auto-selects without prompting

## Intent

When multiple spec directories exist under `specs/`, the phase engine must not
hang waiting for user input in test/CI mode. In `FLOWAI_TESTING=1` mode it must
auto-select (newest by alphabetical sort) and continue without prompting the user.

This guards the `flowai_phase_resolve_feature_dir` change that added interactive
selection for human use while preserving deterministic behaviour in CI.

## Preconditions (Given)

- `jq` is installed.
- Project initialized (`flowai init`).
- Two spec directories exist: `specs/feature-a/` and `specs/feature-b/`, each
  with at least a `spec.md`.
- `.flowai/signals/spec.ready` exists.
- `FLOWAI_TEST_SKIP_AI=1`.

## Action (When)

```bash
FLOWAI_TEST_SKIP_AI=1 flowai run plan
```

## Expected outcome (Then)

- **Exit code:** `0`.
- Output does **not** contain "please choose one" (no interactive prompt fired).

## Automated checks

`flowai_test_s_cli_035` in `tests/suites/lifecycle_happy.sh`.
