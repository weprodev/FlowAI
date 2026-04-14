#!/usr/bin/env bash
# FlowAI test suite — wait UI (single-line progress, rank resolution, spin lock)
# Tests rank mapping, spin lock acquire/release, and guard-condition early returns.
# shellcheck shell=bash
#
# Isolated temp projects use: env FLOWAI_DIR=… FLOWAI_HOME=… bash -s <<'EOS' … EOS
# so ShellCheck does not treat exports as lost subshell assignments (SC2030/SC2031).

source "$FLOWAI_HOME/src/core/log.sh"

# ─── WUI-001: Rank resolution for known phases ────────────────────────────────
flowai_test_s_wui_001() {
  local id="WUI-001"
  local scratch
  scratch="$(mktemp -d)"
  local result
  result="$(env FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/wait_ui.sh"
printf '%s ' "$(flowai_wait_ui_resolve_rank "Plan Phase")"
printf '%s ' "$(flowai_wait_ui_resolve_rank "Tasks Phase")"
printf '%s ' "$(flowai_wait_ui_resolve_rank "Implement Phase")"
printf '%s'  "$(flowai_wait_ui_resolve_rank "Review Phase")"
EOS
)"
  if [[ "$result" == "10 20 30 40" ]]; then
    flowai_test_pass "$id" "Rank resolution for known phases (Plan=10 Tasks=20 Implement=30 Review=40)"
  else
    printf 'FAIL %s: expected "10 20 30 40", got "%s"\n' "$id" "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── WUI-002: Rank resolution for revision labels ─────────────────────────────
flowai_test_s_wui_002() {
  local id="WUI-002"
  local scratch
  scratch="$(mktemp -d)"
  local result
  result="$(env FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/wait_ui.sh"
printf '%s ' "$(flowai_wait_ui_resolve_rank "Plan revision")"
printf '%s'  "$(flowai_wait_ui_resolve_rank "Tasks Revision")"
EOS
)"
  if [[ "$result" == "11 21" ]]; then
    flowai_test_pass "$id" "Rank resolution for revision labels (Plan revision=11 Tasks Revision=21)"
  else
    printf 'FAIL %s: expected "11 21", got "%s"\n' "$id" "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── WUI-003: Unknown label returns RANK_UNKNOWN (99) ─────────────────────────
flowai_test_s_wui_003() {
  local id="WUI-003"
  local scratch
  scratch="$(mktemp -d)"
  local result
  result="$(env FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/wait_ui.sh"
flowai_wait_ui_resolve_rank "Something random"
EOS
)"
  if [[ "$result" == "99" ]]; then
    flowai_test_pass "$id" "Unknown label returns RANK_UNKNOWN (99)"
  else
    printf 'FAIL %s: expected "99", got "%s"\n' "$id" "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── WUI-004: Spin lock acquire and release ───────────────────────────────────
flowai_test_s_wui_004() {
  local id="WUI-004"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/signals"
  local rc=0
  env FLOWAI_HOME="$FLOWAI_HOME" SIGNALS_DIR="$scratch/signals" bash -s <<'EOS' || rc=$?
source "$FLOWAI_HOME/src/core/wait_ui.sh"
_flowai_wait_ui_spin_lock
EOS
  local lock_dir="$scratch/signals/flowai_wait_ui_spinlock"
  if [[ "$rc" -ne 0 ]]; then
    printf 'FAIL %s: spin_lock returned %s, expected 0\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    rm -rf "$scratch"
    return
  fi
  if [[ ! -d "$lock_dir" ]]; then
    printf 'FAIL %s: spinlock directory not created\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    rm -rf "$scratch"
    return
  fi
  # Now unlock
  local rc2=0
  env FLOWAI_HOME="$FLOWAI_HOME" SIGNALS_DIR="$scratch/signals" bash -s <<'EOS' || rc2=$?
source "$FLOWAI_HOME/src/core/wait_ui.sh"
_flowai_wait_ui_spin_unlock
EOS
  if [[ -d "$lock_dir" ]]; then
    printf 'FAIL %s: spinlock directory not removed after unlock\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  else
    flowai_test_pass "$id" "Spin lock acquire creates dir, release removes it"
  fi
  rm -rf "$scratch"
}

# ─── WUI-005: Spin lock timeout when already held ─────────────────────────────
flowai_test_s_wui_005() {
  local id="WUI-005"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/signals/flowai_wait_ui_spinlock"
  local rc=0
  # Set max iterations to 2 (0.1s total) instead of default 400 (20s).
  env FLOWAI_HOME="$FLOWAI_HOME" SIGNALS_DIR="$scratch/signals" FLOWAI_SPINLOCK_MAX_ITER=2 \
    bash -c 'source "$FLOWAI_HOME/src/core/wait_ui.sh"; _flowai_wait_ui_spin_lock' \
    2>/dev/null || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    flowai_test_pass "$id" "Spin lock times out (rc=$rc) when already held"
  else
    printf 'FAIL %s: expected non-zero rc when lock already held, got 0\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── WUI-006: claim_or_skip returns 1 during FLOWAI_TESTING=1 ─────────────────
flowai_test_s_wui_006() {
  local id="WUI-006"
  local scratch
  scratch="$(mktemp -d)"
  local rc=0
  env FLOWAI_HOME="$FLOWAI_HOME" FLOWAI_TESTING=1 bash -s <<'EOS' || rc=$?
source "$FLOWAI_HOME/src/core/wait_ui.sh"
flowai_wait_ui_claim_or_skip 10
EOS
  if [[ "$rc" -eq 1 ]]; then
    flowai_test_pass "$id" "claim_or_skip returns 1 during FLOWAI_TESTING=1"
  else
    printf 'FAIL %s: expected rc=1, got %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── WUI-007: release_if_owner is safe during testing mode ────────────────────
flowai_test_s_wui_007() {
  local id="WUI-007"
  local scratch
  scratch="$(mktemp -d)"
  local rc=0
  env FLOWAI_HOME="$FLOWAI_HOME" FLOWAI_TESTING=1 bash -s <<'EOS' || rc=$?
source "$FLOWAI_HOME/src/core/wait_ui.sh"
flowai_wait_ui_release_if_owner 10
EOS
  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "release_if_owner returns 0 during FLOWAI_TESTING=1"
  else
    printf 'FAIL %s: expected rc=0, got %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── WUI-008: clear_line is no-op during testing ──────────────────────────────
flowai_test_s_wui_008() {
  local id="WUI-008"
  local scratch
  scratch="$(mktemp -d)"
  local rc=0
  env FLOWAI_HOME="$FLOWAI_HOME" FLOWAI_TESTING=1 bash -s <<'EOS' || rc=$?
source "$FLOWAI_HOME/src/core/wait_ui.sh"
flowai_wait_ui_clear_line
EOS
  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "clear_line returns 0 during FLOWAI_TESTING=1 (no-op)"
  else
    printf 'FAIL %s: expected rc=0, got %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}
