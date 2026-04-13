#!/usr/bin/env bash
# Minimal test harness for FlowAI — no Bats required; pure bash + diff.
# shellcheck shell=bash

FLOWAI_TESTS_ROOT="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export FLOWAI_HOME="${FLOWAI_HOME:-$FLOWAI_TESTS_ROOT}"
FLOWAI_BIN="${FLOWAI_TESTS_ROOT}/bin/flowai"

FLOWAI_TEST_FAILURES=0

# Centralized skip helpers for optional dependencies (set via tests/run gating).
flowai_test_skip_if_missing_jq() {
  local id="$1"
  local msg="$2"
  if [[ "${FLOWAI_TEST_SKIP_JQ:-0}" == "1" ]]; then
    printf 'ok  %s — %s (skipped: jq not installed)\n' "$id" "$msg"
    return 0
  fi
  return 1
}

flowai_test_skip_if_missing_tmux() {
  local id="$1"
  local msg="$2"
  if [[ "${FLOWAI_TEST_SKIP_TMUX:-0}" == "1" ]]; then
    printf 'ok  %s — %s (skipped: tmux not installed)\n' "$id" "$msg"
    return 0
  fi
  return 1
}

# Run flowai with args; capture stdout/stderr/rc. Does not use set -e around the invoke.
flowai_test_invoke() {
  local out err
  out="$(mktemp)"
  err="$(mktemp)"
  set +e
  "$FLOWAI_BIN" "$@" >"$out" 2>"$err"
  local rc=$?
  set -e
  FLOWAI_TEST_STDOUT="$(cat "$out")"
  FLOWAI_TEST_STDERR="$(cat "$err")"
  FLOWAI_TEST_RC=$rc
  FLOWAI_TEST_COMBINED="$(cat "$out" "$err" 2>/dev/null || true)"
  rm -f "$out" "$err"
}

# Run flowai with args from a working directory (e.g. temp project).
flowai_test_invoke_in_dir() {
  local workdir="$1"
  shift
  local out err
  out="$(mktemp)"
  err="$(mktemp)"
  set +e
  (cd "$workdir" || exit 99
   FLOWAI_DIR="$workdir/.flowai" "$FLOWAI_BIN" "$@") >"$out" 2>"$err"
  local rc=$?
  set -e
  FLOWAI_TEST_STDOUT="$(cat "$out")"
  FLOWAI_TEST_STDERR="$(cat "$err")"
  FLOWAI_TEST_RC=$rc
  FLOWAI_TEST_COMBINED="$(cat "$out" "$err" 2>/dev/null || true)"
  rm -f "$out" "$err"
}

# Same as flowai_test_invoke_in_dir but prefixes env (e.g. FLOWAI_TEST_SKIP_AI=1).
flowai_test_invoke_in_dir_env() {
  local workdir="$1"
  shift
  local out err
  out="$(mktemp)"
  err="$(mktemp)"
  set +e
  (cd "$workdir" || exit 99
   env FLOWAI_DIR="$workdir/.flowai" "$@") >"$out" 2>"$err"
  local rc=$?
  set -e
  FLOWAI_TEST_STDOUT="$(cat "$out")"
  FLOWAI_TEST_STDERR="$(cat "$err")"
  FLOWAI_TEST_RC=$rc
  FLOWAI_TEST_COMBINED="$(cat "$out" "$err" 2>/dev/null || true)"
  rm -f "$out" "$err"
}

# PATH with every directory entry that contains an executable named `cmd` removed (repeat until none).
# Uses `$PATH/$cmd` checks so Homebrew symlinks do not leave duplicate resolution paths.
flowai_test_path_excluding_cmd() {
  local cmd="$1"
  local result="$PATH" new changed
  while true; do
    changed=0
    new=""
    local IFS=:
    for d in $result; do
      [[ -z "$d" ]] && continue
      if [[ -x "$d/$cmd" ]]; then
        changed=1
        continue
      fi
      new="${new:+$new:}$d"
    done
    result="$new"
    [[ "$changed" -eq 0 ]] && break
  done
  printf '%s\n' "$result"
}

# Temp directory whose only PATH entry is .../bin with bash + dirname (bin/flowai uses dirname before jq checks).
flowai_test_mktemp_fake_bash_only_root() {
  local root bin bashpath dirpath
  root="$(mktemp -d)"
  bin="$root/bin"
  mkdir -p "$bin"
  bashpath="$(command -v bash)"
  dirpath="$(command -v dirname)"
  ln -sf "$bashpath" "$bin/bash"
  ln -sf "$dirpath" "$bin/dirname"
  printf '%s\n' "$root"
}

flowai_test_assert_rc() {
  local want="$1"
  local id="${2:-}"
  if [[ "${FLOWAI_TEST_RC:-}" != "$want" ]]; then
    printf 'FAIL %s: expected exit %s, got %s\n' "$id" "$want" "${FLOWAI_TEST_RC:-}" >&2
    printf -- '--- stdout ---\n%s\n--- stderr ---\n%s\n' "$FLOWAI_TEST_STDOUT" "$FLOWAI_TEST_STDERR" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi
  return 0
}

flowai_test_assert_combined_contains() {
  local needle="$1"
  local id="${2:-}"
  if [[ "$FLOWAI_TEST_COMBINED" != *"$needle"* ]]; then
    printf 'FAIL %s: output must contain %q\n' "$id" "$needle" >&2
    printf -- '--- combined ---\n%s\n' "$FLOWAI_TEST_COMBINED" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi
  return 0
}

flowai_test_assert_path_exists() {
  local path="$1"
  local id="${2:-}"
  if [[ ! -e "$path" ]]; then
    printf 'FAIL %s: expected path to exist: %q\n' "$id" "$path" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi
  return 0
}

flowai_test_assert_combined_not_contains() {
  local needle="$1"
  local id="${2:-}"
  if [[ "$FLOWAI_TEST_COMBINED" == *"$needle"* ]]; then
    printf 'FAIL %s: output must NOT contain %q\n' "$id" "$needle" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi
  return 0
}

flowai_test_pass() {
  local id="$1"
  local title="$2"
  printf 'ok  %s — %s\n' "$id" "$title"
}
