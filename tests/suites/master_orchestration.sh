#!/usr/bin/env bash
# Master orchestration tests — structural and regex validation for master.sh.
#
# master.sh is a top-level script (set -euo pipefail, launches background watchers,
# runs interactive AI sessions), so we do NOT source it. Tests use grep/pattern
# analysis on the source file or validate extracted regex patterns inline.
# shellcheck shell=bash
# shellcheck disable=SC2016  # grep patterns match literal $ in source files

# shellcheck source=../../src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"

MASTER_SH="$FLOWAI_HOME/src/phases/master.sh"

# ─── MSTR-001: master.sh sources phase.sh and ai.sh ───────────────────────────
# Prevents: missing core dependencies causing immediate crash on boot.
flowai_test_s_mstr_001() {
  local id="MSTR-001"
  if grep -qF 'source "$FLOWAI_HOME/src/core/phase.sh"' "$MASTER_SH" 2>/dev/null \
    && grep -qF 'source "$FLOWAI_HOME/src/core/ai.sh"' "$MASTER_SH" 2>/dev/null; then
    flowai_test_pass "$id" "master.sh sources phase.sh and ai.sh"
  else
    printf 'FAIL %s: master.sh must source both phase.sh and ai.sh\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── MSTR-002: Verdict regex rejects "VERDICT: MAYBE APPROVED" ────────────────
# Prevents: false positive when AI hedges with a qualifier before APPROVED.
flowai_test_s_mstr_002() {
  local id="MSTR-002"
  local verdict_line='VERDICT: MAYBE APPROVED'
  local is_approved=false
  if [[ "$verdict_line" =~ ^[[:space:]]*VERDICT:[[:space:]]*APPROVED[[:space:]]*$ ]]; then
    is_approved=true
  fi
  if ! $is_approved; then
    flowai_test_pass "$id" "verdict MAYBE APPROVED does not match strict APPROVED regex"
  else
    printf 'FAIL %s: MAYBE APPROVED must not match\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── MSTR-003: Verdict regex accepts "VERDICT: APPROVED" with whitespace ──────
# Ensures: leading/trailing/internal whitespace around VERDICT: APPROVED is tolerated.
flowai_test_s_mstr_003() {
  local id="MSTR-003"
  local pass_count=0
  local total=0
  local line
  for line in \
    'VERDICT: APPROVED' \
    '  VERDICT:  APPROVED  ' \
    '	VERDICT:	APPROVED	' \
    'VERDICT:APPROVED'; do
    total=$((total + 1))
    if [[ "$line" =~ ^[[:space:]]*VERDICT:[[:space:]]*APPROVED[[:space:]]*$ ]]; then
      pass_count=$((pass_count + 1))
    fi
  done
  if [[ "$pass_count" -eq "$total" ]]; then
    flowai_test_pass "$id" "verdict APPROVED matches with various whitespace ($total variants)"
  else
    printf 'FAIL %s: only %s/%s whitespace variants matched\n' "$id" "$pass_count" "$total" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── MSTR-004: _master_tasks_run_verdict function exists ──────────────────────
# Prevents: accidental rename or removal of the single-round binding review function.
flowai_test_s_mstr_004() {
  local id="MSTR-004"
  if grep -qE '^_master_tasks_run_verdict\(\)' "$MASTER_SH" 2>/dev/null; then
    flowai_test_pass "$id" "_master_tasks_run_verdict function defined in master.sh"
  else
    printf 'FAIL %s: _master_tasks_run_verdict() not found in master.sh\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── MSTR-005: Dispute escalation uses configurable max rounds ────────────────
# Prevents: hard-coded dispute limit that cannot be overridden via env.
flowai_test_s_mstr_005() {
  local id="MSTR-005"
  if grep -qF 'FLOWAI_TASKS_MAX_DISPUTE_ROUNDS' "$MASTER_SH" 2>/dev/null; then
    flowai_test_pass "$id" "dispute escalation uses FLOWAI_TASKS_MAX_DISPUTE_ROUNDS"
  else
    printf 'FAIL %s: FLOWAI_TASKS_MAX_DISPUTE_ROUNDS not referenced in master.sh\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── MSTR-006: master.sh handles pipeline_complete event ─────────────────────
# Prevents: pipeline finishing silently without user-visible completion message.
flowai_test_s_mstr_006() {
  local id="MSTR-006"
  if grep -qF '"pipeline_complete"' "$MASTER_SH" 2>/dev/null \
    && grep -qF 'Pipeline complete' "$MASTER_SH" 2>/dev/null; then
    flowai_test_pass "$id" "master.sh emits pipeline_complete event and completion message"
  else
    printf 'FAIL %s: pipeline_complete event or completion message missing\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── MSTR-007: Rejection context written to signals/tasks.rejection_context ───
# Prevents: tasks agent not receiving revision feedback after Master REJECT verdict.
flowai_test_s_mstr_007() {
  local id="MSTR-007"
  if grep -qF 'tasks.rejection_context' "$MASTER_SH" 2>/dev/null; then
    flowai_test_pass "$id" "rejection context written to signals/tasks.rejection_context"
  else
    printf 'FAIL %s: tasks.rejection_context not found in master.sh\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── MSTR-008: _master_check_events handles event file shrinkage ─────────────
# Prevents: infinite loop or missed events when events.jsonl is truncated/rotated.
flowai_test_s_mstr_008() {
  local id="MSTR-008"
  # The line counter reset pattern: if total_lines < last_processed, reset to 0
  if grep -qF '_master_last_processed_line=0' "$MASTER_SH" 2>/dev/null \
    && grep -qE '\$total_lines.*-lt.*\$_master_last_processed_line' "$MASTER_SH" 2>/dev/null; then
    flowai_test_pass "$id" "_master_check_events resets line counter on event file shrinkage"
  else
    printf 'FAIL %s: event file shrinkage guard not found in master.sh\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── MSTR-009: Post-QA review uses READY_FOR_HUMAN_SIGNOFF / NEEDS_FOLLOW_UP ─
# Prevents: Master post-QA review prompt missing structured verdict markers.
flowai_test_s_mstr_009() {
  local id="MSTR-009"
  if grep -qF 'READY_FOR_HUMAN_SIGNOFF' "$MASTER_SH" 2>/dev/null \
    && grep -qF 'NEEDS_FOLLOW_UP' "$MASTER_SH" 2>/dev/null; then
    flowai_test_pass "$id" "post-QA review uses READY_FOR_HUMAN_SIGNOFF and NEEDS_FOLLOW_UP markers"
  else
    printf 'FAIL %s: post-QA verdict markers missing in master.sh\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── MSTR-010: _master_handle_phase_errors_from_batch skips menu in testing ───
# Prevents: interactive gum menu blocking CI/test runs when a phase error fires.
flowai_test_s_mstr_010() {
  local id="MSTR-010"
  if grep -qF 'FLOWAI_TESTING' "$MASTER_SH" 2>/dev/null \
    && grep -qF 'recovery menu skipped' "$MASTER_SH" 2>/dev/null; then
    flowai_test_pass "$id" "_master_handle_phase_errors_from_batch skips menu in FLOWAI_TESTING=1"
  else
    printf 'FAIL %s: FLOWAI_TESTING guard for error recovery menu not found\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}
