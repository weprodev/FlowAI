---
id: UC-VER-006
layer: core
bounded_context: version
automated_test: flowai_test_s_ver_006
status: implemented
---

# UC-VER-006 — Cache write and read round-trip

## Intent
Version cache persistence works correctly.

## Preconditions (Given)
- Cache dir points to a temp location.

## Action (When)
Write "0.5.0" to cache, then read it back.

## Expected outcome (Then)
- Returns "0.5.0".

## Automated checks
Implemented by `flowai_test_s_ver_006` in `tests/suites/version_check.sh`.
