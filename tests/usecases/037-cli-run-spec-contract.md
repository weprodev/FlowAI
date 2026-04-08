---
id: UC-CLI-037
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_037
status: implemented
---

# UC-CLI-037 — `flowai run spec` contract (no AI)

## Intent

Full **spec** execution invokes an agent — not suitable for deterministic CI.
This contract validates the spec phase resolves the feature directory and reaches
the "ready to run AI" point.

Tests set **`FLOWAI_TEST_SKIP_AI=1`**, which makes `src/phases/spec.sh` exit
**0** immediately after validating the fixture.

Without this test, the previously-missing `FLOWAI_TEST_SKIP_AI` guard in
`spec.sh` would go undetected.

## Preconditions (Given)

- `jq` is installed.
- Project initialized (`flowai init`).
- `specs/<feature>/` directory exists.
- `FLOWAI_TEST_SKIP_AI=1`.

## Action (When)

```bash
FLOWAI_TEST_SKIP_AI=1 flowai run spec
```

## Expected outcome (Then)

- **Exit code:** `0`.
- Output mentions the contract / skip path.

## Automated checks

`flowai_test_s_cli_037` in `tests/suites/lifecycle_happy.sh`.
