---
id: UC-CLI-034
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_034
status: implemented
---

# UC-CLI-034 — `flowai run review` contract (no AI)

## Intent

Full **review** execution invokes an agent and awaits human approval — not suitable
for deterministic CI. This contract test validates that the review phase correctly
resolves the feature directory, reads upstream signals, and reaches the
"ready to run AI" point.

Tests set **`FLOWAI_TEST_SKIP_AI=1`**, which makes `src/phases/review.sh` exit
**0** immediately after validating the fixture.

Without this test, the missing `FLOWAI_TEST_SKIP_AI` guard in `review.sh` (and
the absent approval gate) would both go undetected.

## Preconditions (Given)

- `jq` is installed.
- Project has been initialized (`flowai init`).
- `specs/<feature>/tasks.md` exists.
- `.flowai/signals/impl.code_complete.ready` exists (implement has produced code for QA).
- Environment: `FLOWAI_TEST_SKIP_AI=1` (test harness only).

## Action (When)

```bash
FLOWAI_TEST_SKIP_AI=1 flowai run review
```

## Expected outcome (Then)

- **Exit code:** `0`.
- Output mentions the contract / skip path (e.g. "contract test").

## Automated checks

`flowai_test_s_cli_034` in `tests/suites/lifecycle_happy.sh`.
