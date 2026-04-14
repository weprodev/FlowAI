---
id: UC-VER-001
layer: core
bounded_context: version
automated_test: flowai_test_s_ver_001
status: implemented
---

# UC-VER-001 — Version compare detects outdated

## Intent
Semver comparison returns 0 when current < latest.

## Preconditions (Given)
- `version-check.sh` is sourced.

## Action (When)
Call `flowai_version_compare "0.1.0" "0.2.0"`.

## Expected outcome (Then)
- Returns 0 (outdated).

## Automated checks
Implemented by `flowai_test_s_ver_001` in `tests/suites/version_check.sh`.
