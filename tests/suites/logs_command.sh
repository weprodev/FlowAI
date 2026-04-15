#!/usr/bin/env bash
# Logs command — tests for src/commands/logs.sh
# Expects tests/lib/harness.sh sourced first (see tests/run.sh).
# shellcheck shell=bash
# shellcheck disable=SC2016  # grep patterns contain $ for literal matching, not shell expansion

# shellcheck source=../../src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"

LOGS_SRC="$FLOWAI_HOME/src/commands/logs.sh"

# LOGS-001: flowai logs without a running session exits 1 with error
flowai_test_s_logs_001() {
  if flowai_test_skip_if_missing_tmux "LOGS-001" "flowai logs without session exits 1"; then return 0; fi
  flowai_test_invoke logs
  flowai_test_assert_rc 1 "LOGS-001" || return
  flowai_test_assert_combined_contains "not running" "LOGS-001" || return
  flowai_test_pass "LOGS-001" "flowai logs without a running session exits 1 with error"
}

# LOGS-002: logs.sh requires tmux (command -v tmux check present)
flowai_test_s_logs_002() {
  local id="LOGS-002"
  if ! grep -q 'command -v tmux' "$LOGS_SRC"; then
    printf 'FAIL %s: logs.sh does not check for tmux\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi
  flowai_test_pass "$id" "logs.sh requires tmux (command -v tmux check present)"
}

# LOGS-003: logs.sh defaults to "master" phase when no argument given
flowai_test_s_logs_003() {
  local id="LOGS-003"
  if ! grep -q 'phase="${1:-master}"' "$LOGS_SRC"; then
    printf 'FAIL %s: logs.sh does not default to master phase\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi
  flowai_test_pass "$id" "logs.sh defaults to master phase when no argument given"
}

# LOGS-004: logs.sh uses less -R for interactive display
flowai_test_s_logs_004() {
  local id="LOGS-004"
  if ! grep -q 'less -RXF' "$LOGS_SRC"; then
    printf 'FAIL %s: logs.sh does not use less -R for interactive display\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi
  flowai_test_pass "$id" "logs.sh uses less -R for interactive display"
}

# LOGS-005: logs.sh validates phase name against running tmux windows
flowai_test_s_logs_005() {
  local id="LOGS-005"
  if ! grep -q 'list-windows' "$LOGS_SRC"; then
    printf 'FAIL %s: logs.sh does not validate phase via tmux list-windows\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi
  flowai_test_pass "$id" "logs.sh validates phase name against running tmux windows"
}

# LOGS-006: logs.sh sources session.sh for session name resolution
flowai_test_s_logs_006() {
  local id="LOGS-006"
  if ! grep -q 'source.*session\.sh' "$LOGS_SRC"; then
    printf 'FAIL %s: logs.sh does not source session.sh\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi
  flowai_test_pass "$id" "logs.sh sources session.sh for session name resolution"
}
