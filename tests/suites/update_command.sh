#!/usr/bin/env bash
# Update command — tests for flowai update (src/commands/update.sh).
# Expects tests/lib/harness.sh sourced first (see tests/run.sh).
# shellcheck shell=bash

source "$FLOWAI_HOME/src/core/log.sh"

UPDATE_SRC="$FLOWAI_HOME/src/commands/update.sh"

# UPD-001: flowai update --help exits 0 and shows usage
flowai_test_s_upd_001() {
  flowai_test_invoke update --help
  flowai_test_assert_rc 0 "UPD-001" || return
  flowai_test_assert_combined_contains "Self-update FlowAI" "UPD-001" || return
  flowai_test_assert_combined_contains "Usage:" "UPD-001" || return
  flowai_test_assert_combined_contains "--check" "UPD-001" || return
  flowai_test_assert_combined_contains "--version" "UPD-001" || return
  flowai_test_pass "UPD-001" "flowai update --help exits 0 and shows usage"
}

# UPD-002: flowai update --check exits 0 (tolerant of network errors)
flowai_test_s_upd_002() {
  flowai_test_invoke update --check
  # --check may fail if there is no network, but it should never crash with a
  # usage error.  Accept rc=0 (success / up-to-date) or rc that still produced
  # meaningful output (not a shell syntax error).
  if [[ "$FLOWAI_TEST_RC" -eq 0 ]]; then
    flowai_test_pass "UPD-002" "flowai update --check exits 0"
    return
  fi
  # Non-zero is acceptable only if the output does NOT look like a usage/crash error.
  if [[ "$FLOWAI_TEST_COMBINED" == *"Usage:"* ]] || [[ "$FLOWAI_TEST_COMBINED" == *"syntax error"* ]]; then
    printf 'FAIL UPD-002: --check crashed with usage/syntax error (rc=%s)\n' "$FLOWAI_TEST_RC" >&2
    printf -- '--- combined ---\n%s\n' "$FLOWAI_TEST_COMBINED" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi
  flowai_test_pass "UPD-002" "flowai update --check ran without crash (rc=$FLOWAI_TEST_RC, likely no network)"
}

# UPD-003: _update_detect_mode function exists in update.sh
flowai_test_s_upd_003() {
  local id="UPD-003"
  if grep -q '_update_detect_mode()' "$UPDATE_SRC"; then
    flowai_test_pass "$id" "_update_detect_mode function exists in update.sh"
  else
    printf 'FAIL %s: _update_detect_mode() not found in %s\n' "$id" "$UPDATE_SRC" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UPD-004: update.sh sources version-check.sh for semver comparison
flowai_test_s_upd_004() {
  local id="UPD-004"
  if grep -q 'source.*version-check\.sh' "$UPDATE_SRC"; then
    flowai_test_pass "$id" "update.sh sources version-check.sh for semver comparison"
  else
    printf 'FAIL %s: update.sh does not source version-check.sh\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UPD-005: update.sh supports --version flag for targeted version
flowai_test_s_upd_005() {
  local id="UPD-005"
  if grep -q '\-\-version' "$UPDATE_SRC"; then
    flowai_test_pass "$id" "update.sh supports --version flag for targeted version"
  else
    printf 'FAIL %s: --version flag not found in update.sh\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UPD-006: _update_download_and_install uses curl with --max-time for timeout safety
flowai_test_s_upd_006() {
  local id="UPD-006"
  if grep -q 'curl.*--max-time' "$UPDATE_SRC"; then
    flowai_test_pass "$id" "_update_download_and_install uses curl with --max-time for timeout safety"
  else
    printf 'FAIL %s: curl --max-time not found in _update_download_and_install\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}
