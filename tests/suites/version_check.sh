#!/usr/bin/env bash
# FlowAI test suite — version check (cached update notification)
# Tests for semver comparison, cache round-trip, and notification logic.
# shellcheck shell=bash
#
# Temp projects: env … bash -s <<'EOS' … EOS (avoids SC2030/SC2031 on export-in-subshell).

source "$FLOWAI_HOME/src/core/log.sh"

# ─── VER-001: version_compare detects outdated (0.1.0 < 0.2.0) ────────────────
flowai_test_s_ver_001() {
  local id="VER-001"
  local scratch
  scratch="$(mktemp -d)"
  local rc=0
  env FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_UPDATE_CACHE_DIR="$scratch/.cache" \
    FLOWAI_UPDATE_CACHE_FILE="$scratch/.cache/update-check" \
    bash -s <<'EOS' || rc=$?
source "$FLOWAI_HOME/src/core/version-check.sh"
flowai_version_compare "0.1.0" "0.2.0"
EOS
  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "version_compare detects outdated (0.1.0 < 0.2.0)"
  else
    printf 'FAIL %s: expected rc=0 (outdated), got %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── VER-002: version_compare detects current (0.2.0 vs 0.2.0) ────────────────
flowai_test_s_ver_002() {
  local id="VER-002"
  local scratch
  scratch="$(mktemp -d)"
  local rc=0
  env FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_UPDATE_CACHE_DIR="$scratch/.cache" \
    FLOWAI_UPDATE_CACHE_FILE="$scratch/.cache/update-check" \
    bash -s <<'EOS' || rc=$?
source "$FLOWAI_HOME/src/core/version-check.sh"
flowai_version_compare "0.2.0" "0.2.0"
EOS
  if [[ "$rc" -eq 1 ]]; then
    flowai_test_pass "$id" "version_compare detects current (0.2.0 vs 0.2.0)"
  else
    printf 'FAIL %s: expected rc=1 (not outdated), got %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── VER-003: version_compare detects newer (0.3.0 vs 0.2.0) ──────────────────
flowai_test_s_ver_003() {
  local id="VER-003"
  local scratch
  scratch="$(mktemp -d)"
  local rc=0
  env FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_UPDATE_CACHE_DIR="$scratch/.cache" \
    FLOWAI_UPDATE_CACHE_FILE="$scratch/.cache/update-check" \
    bash -s <<'EOS' || rc=$?
source "$FLOWAI_HOME/src/core/version-check.sh"
flowai_version_compare "0.3.0" "0.2.0"
EOS
  if [[ "$rc" -eq 1 ]]; then
    flowai_test_pass "$id" "version_compare detects newer (0.3.0 vs 0.2.0)"
  else
    printf 'FAIL %s: expected rc=1 (not outdated), got %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── VER-004: version_compare strips v prefix ─────────────────────────────────
flowai_test_s_ver_004() {
  local id="VER-004"
  local scratch
  scratch="$(mktemp -d)"
  local rc=0
  env FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_UPDATE_CACHE_DIR="$scratch/.cache" \
    FLOWAI_UPDATE_CACHE_FILE="$scratch/.cache/update-check" \
    bash -s <<'EOS' || rc=$?
source "$FLOWAI_HOME/src/core/version-check.sh"
flowai_version_compare "v0.1.0" "v0.2.0"
EOS
  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "version_compare strips v prefix"
  else
    printf 'FAIL %s: expected rc=0 (outdated with v prefix), got %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── VER-005: version_compare handles patch versions ──────────────────────────
flowai_test_s_ver_005() {
  local id="VER-005"
  local scratch
  scratch="$(mktemp -d)"
  local rc_outdated=0 rc_newer=0
  env FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_UPDATE_CACHE_DIR="$scratch/.cache" \
    FLOWAI_UPDATE_CACHE_FILE="$scratch/.cache/update-check" \
    bash -s <<'EOS' || rc_outdated=$?
source "$FLOWAI_HOME/src/core/version-check.sh"
flowai_version_compare "1.2.3" "1.2.4"
EOS
  env FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_UPDATE_CACHE_DIR="$scratch/.cache" \
    FLOWAI_UPDATE_CACHE_FILE="$scratch/.cache/update-check" \
    bash -s <<'EOS' || rc_newer=$?
source "$FLOWAI_HOME/src/core/version-check.sh"
flowai_version_compare "1.2.4" "1.2.3"
EOS
  if [[ "$rc_outdated" -eq 0 && "$rc_newer" -eq 1 ]]; then
    flowai_test_pass "$id" "version_compare handles patch versions"
  else
    printf 'FAIL %s: expected rc=0,1 for patch compare, got %s,%s\n' "$id" "$rc_outdated" "$rc_newer" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── VER-006: cache_write and cache_read round-trip ───────────────────────────
flowai_test_s_ver_006() {
  local id="VER-006"
  local scratch
  scratch="$(mktemp -d)"
  local result
  result="$(env FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_UPDATE_CACHE_DIR="$scratch/.cache" \
    FLOWAI_UPDATE_CACHE_FILE="$scratch/.cache/update-check" \
    bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/version-check.sh"
_version_check_cache_write "0.5.0"
_version_check_cache_read_latest
EOS
)"
  if [[ "$result" == "0.5.0" ]]; then
    flowai_test_pass "$id" "cache_write and cache_read round-trip"
  else
    printf 'FAIL %s: expected "0.5.0", got "%s"\n' "$id" "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── VER-007: cache_is_fresh returns 1 for missing file ──────────────────────
flowai_test_s_ver_007() {
  local id="VER-007"
  local scratch
  scratch="$(mktemp -d)"
  local rc=0
  env FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_UPDATE_CACHE_DIR="$scratch/.cache" \
    FLOWAI_UPDATE_CACHE_FILE="$scratch/.cache/update-check" \
    bash -s <<'EOS' || rc=$?
source "$FLOWAI_HOME/src/core/version-check.sh"
_version_check_cache_is_fresh
EOS
  if [[ "$rc" -eq 1 ]]; then
    flowai_test_pass "$id" "cache_is_fresh returns 1 for missing file"
  else
    printf 'FAIL %s: expected rc=1 (not fresh), got %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── VER-008: notify skips in test mode ───────────────────────────────────────
flowai_test_s_ver_008() {
  local id="VER-008"
  local scratch
  scratch="$(mktemp -d)"
  local output rc=0
  # Run in a standalone subshell, capture output and exit code independently
  # to avoid SC2030/SC2031 (subshell variable assignment inside $()).
  output="$(env FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_TESTING=1 \
    FLOWAI_UPDATE_CACHE_DIR="$scratch/.cache" \
    FLOWAI_UPDATE_CACHE_FILE="$scratch/.cache/update-check" \
    bash -s 2>&1 <<'EOS'
source "$FLOWAI_HOME/src/core/version-check.sh"
flowai_version_check_notify
EOS
)" || rc=$?
  if [[ "$rc" -eq 0 && -z "$output" ]]; then
    flowai_test_pass "$id" "notify skips in test mode"
  else
    printf 'FAIL %s: expected rc=0 with no output, got rc=%s output="%s"\n' "$id" "$rc" "$output" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}
