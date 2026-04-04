---
id: UC-CLI-013
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_013
status: implemented
---

# UC-CLI-013 — `flowai run plan` contract (no AI)

## Intent

Full **plan** execution invokes an agent and is not suitable for deterministic CI. This use case still needs a **contract**: after `init`, with a feature folder containing `spec.md` and upstream `spec.ready`, the phase script must reach the “ready to run AI” point.

Tests set **`FLOWAI_TEST_SKIP_AI=1`**, which makes `src/phases/plan.sh` exit **0** immediately after validating the fixture (see log line containing “contract test”). This is **not** a substitute for manual/agent verification of a real plan run.

## Preconditions (Given)

- `jq` is installed.
- Project has been initialized (`flowai init`).
- `specs/<feature>/spec.md` exists.
- `.flowai/signals/spec.ready` exists (upstream spec phase complete).
- Environment: `FLOWAI_TEST_SKIP_AI=1` (test harness only).

## Action (When)

```bash
FLOWAI_TEST_SKIP_AI=1 flowai run plan
```

## Expected outcome (Then)

- **Exit code:** `0`.
- Output mentions the contract / skip path (e.g. “contract test”).

## Automated checks

`flowai_test_s_cli_013` in `tests/suites/lifecycle_happy.sh`.
