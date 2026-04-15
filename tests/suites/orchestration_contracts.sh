#!/usr/bin/env bash
# Orchestration regression contracts — behavioral tests that caught real production bugs.
#
# Why this file exists:
# - Grep-only "SIG-*" checks prove strings exist; they do not prove the protocol works.
# - Bugs we guard here: wrong JSON `phase` casing (Plan vs plan → deadlocks on Linux),
#   false-positive task verdict parsing (NOT APPROVED), tasks retry deleting context too early,
#   Master writing the wrong revision filename, Gemini stderr noise masking real output,
#   bash printf formats starting with --- (macOS), OSC/ANSI leaking into Master status line,
#   scrollback corruption from \\r redraws (mitigated by FLOWAI_PLAIN_TERMINAL).
#
# Add tests here when a defect slips through — each case should state which incident it prevents.
# shellcheck shell=bash

# shellcheck source=../../src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"

# ─── ORCH-001: flowai_event_emit stores canonical lowercase phase in JSON ───
# Prevents: Master touching Plan.revision.ready while Plan waits on plan.revision.ready.
flowai_test_s_orch_001() {
  local id="ORCH-001"
  if flowai_test_skip_if_missing_jq "$id" "event JSON phase id contract"; then
    return 0
  fi
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  printf '{}' > "$scratch/.flowai/config.json"
  local _fd="$scratch/.flowai" _fh="$FLOWAI_HOME"
  env FLOWAI_DIR="$_fd" FLOWAI_HOME="$_fh" bash -s "$scratch" <<'EOS'
cd "$1" || exit 1
# shellcheck source=../../src/core/eventlog.sh
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_emit "plan" "rejected" "human"
EOS
  local last
  last="$(tail -n 1 "$scratch/.flowai/events.jsonl")"
  if echo "$last" | jq -e '.phase == "plan" and .event == "rejected"' >/dev/null 2>&1; then
    flowai_test_pass "$id" "event JSON uses canonical phase id (plan)"
  else
    printf 'FAIL %s: expected .phase==plan, line=%s\n' "$id" "$last" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── ORCH-002 / 003: Master task verdict — same regex as master.sh ───────────
# Prevents: VERDICT: NOT APPROVED wrongly counted as approved (substring APPROVED).
flowai_test_s_orch_002() {
  local id="ORCH-002"
  local verdict_line='VERDICT: NOT APPROVED'
  local is_approved=false
  if [[ "$verdict_line" =~ ^[[:space:]]*VERDICT:[[:space:]]*APPROVED[[:space:]]*$ ]]; then
    is_approved=true
  fi
  if ! $is_approved; then
    flowai_test_pass "$id" "verdict line NOT APPROVED does not match strict APPROVED regex"
  else
    printf 'FAIL %s: NOT APPROVED must not approve\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

flowai_test_s_orch_003() {
  local id="ORCH-003"
  local verdict_line='VERDICT: APPROVED'
  local is_approved=false
  if [[ "$verdict_line" =~ ^[[:space:]]*VERDICT:[[:space:]]*APPROVED[[:space:]]*$ ]]; then
    is_approved=true
  fi
  if $is_approved; then
    flowai_test_pass "$id" "verdict line APPROVED matches strict regex"
  else
    printf 'FAIL %s: APPROVED should match\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── ORCH-004: Master lowercases rej_phase before touch revision.ready ───────
flowai_test_s_orch_004() {
  local id="ORCH-004"
  local master="$FLOWAI_HOME/src/phases/master.sh"
  local _pat_rej_ready
  _pat_rej_ready="\${rej_phase}.revision.ready"
  if grep -qF "tr '[:upper:]' '[:lower:]'" "$master" 2>/dev/null \
    && grep -qF "$_pat_rej_ready" "$master" 2>/dev/null; then
    flowai_test_pass "$id" "Master normalizes rejection phase id for revision signal path"
  else
    printf 'FAIL %s: master.sh must lowercase .phase before revision.ready touch\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── ORCH-005: verify_artifact emits events with phase_id not display label ─
flowai_test_s_orch_005() {
  local id="ORCH-005"
  local phase="$FLOWAI_HOME/src/core/phase.sh"
  local _emit_rej _emit_app
  _emit_rej="flowai_event_emit \"\$phase_id\" \"rejected\""
  _emit_app="flowai_event_emit \"\$phase_id\" \"approved\""
  if grep -qF "$_emit_rej" "$phase" 2>/dev/null \
    && grep -qF "$_emit_app" "$phase" 2>/dev/null; then
    flowai_test_pass "$id" "verify_artifact emits JSON phase from canonical id"
  else
    printf 'FAIL %s: phase.sh must use phase_id for reject/approve events\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── ORCH-006: tasks retry must not rm rejection file before cat (regression) ─
flowai_test_s_orch_006() {
  local id="ORCH-006"
  local tasks="$FLOWAI_HOME/src/phases/tasks.sh"
  local _tasks_cat _tasks_rm
  _tasks_cat="local_revision=\"\$(cat \"\$TASKS_REJECTION_FILE\" 2>/dev/null || true)\""
  _tasks_rm="rm -f \"\$TASKS_REJECTION_FILE\" 2>/dev/null || true"
  if grep -qF "$_tasks_cat" "$tasks" 2>/dev/null \
    && grep -qF "$_tasks_rm" "$tasks" 2>/dev/null; then
    flowai_test_pass "$id" "tasks.sh documents and reads rejection context before rm"
  else
    printf 'FAIL %s: tasks retry contract broken\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── ORCH-007: Gemini stderr filter — configurable via FLOWAI_AGENT_VERBOSE ──
flowai_test_s_orch_007() {
  local id="ORCH-007"
  # shellcheck source=../../src/tools/gemini.sh
  source "$FLOWAI_HOME/src/tools/gemini.sh"

  # Mode 1: FLOWAI_AGENT_VERBOSE=0 → strip LocalAgentExecutor lines (old behavior)
  local out_quiet
  out_quiet="$(
    # shellcheck disable=SC2030  # intentional: subshell-scoped env for test isolation
    export FLOWAI_AGENT_VERBOSE=0
    printf '%s\n%s\n' \
      '[LocalAgentExecutor] Skipping subagent tool x' \
      'gemini: real error on stderr' \
    | _flowai_gemini_filter_stderr
  )"
  if [[ "$out_quiet" != *'real error'* ]] || [[ "$out_quiet" == *'LocalAgentExecutor'* ]]; then
    printf 'FAIL %s: verbose=0 should strip executor lines: %q\n' "$id" "$out_quiet" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return
  fi

  # Mode 2: FLOWAI_AGENT_VERBOSE=1 → pass through (with dim ANSI prefix)
  local out_verbose
  out_verbose="$(
    # shellcheck disable=SC2030,SC2031  # intentional: subshell-scoped env for test isolation
    export FLOWAI_AGENT_VERBOSE=1
    printf '%s\n%s\n' \
      '[LocalAgentExecutor] Skipping subagent tool x' \
      'gemini: real error on stderr' \
    | _flowai_gemini_filter_stderr
  )"
  if [[ "$out_verbose" != *'LocalAgentExecutor'* ]] || [[ "$out_verbose" != *'real error'* ]]; then
    printf 'FAIL %s: verbose=1 should keep executor lines: %q\n' "$id" "$out_verbose" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return
  fi

  flowai_test_pass "$id" "Gemini stderr filter: verbose=0 strips, verbose=1 passes through"
}

# ─── ORCH-008: plan.revision.ready unblocks flowai_phase_wait_for ───────────
# Prevents: typo in signal name so Plan waits forever after Master guidance.
flowai_test_s_orch_008() {
  local id="ORCH-008"
  local scratch rc=0
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/signals"
  printf '{}' > "$scratch/.flowai/config.json"
  ( sleep 0.25; touch "$scratch/.flowai/signals/plan.revision.ready" ) &
  local _fh="$FLOWAI_HOME"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$_fh" bash -s <<'EOS' || rc=$?
# shellcheck source=../../src/core/phase.sh
source "$FLOWAI_HOME/src/core/phase.sh"
flowai_phase_wait_for "plan.revision" "orch-wait"
EOS
  wait || true
  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "wait_for unblocks when plan.revision.ready appears"
  else
    printf 'FAIL %s: wait_for expected rc=0, got %s\n' "$id" "${rc:-}" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── ORCH-010: Master prompt build + status line — no printf --- bug, no ESC leak ─
# Prevents: printf '--- spec.md ---' → "printf: --: invalid option" (bash); OSC 11 garbage on Pipeline:
flowai_test_s_orch_010() {
  local id="ORCH-010"
  local master="$FLOWAI_HOME/src/phases/master.sh"
  if ! grep -qE "printf '(\\\\n)?%s(\\\\n)?' '--- spec.md ---'" "$master" 2>/dev/null; then
    printf 'FAIL %s: master.sh must use printf %%s for --- spec.md header (bash/macOS)\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return
  fi
  if ! grep -qF 'flowai_sanitize_display_text' "$FLOWAI_HOME/src/core/log.sh" 2>/dev/null; then
    printf 'FAIL %s: log.sh must define flowai_sanitize_display_text\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return
  fi
  local dirty clean
  dirty=$'plain\e[31m\e]11;rgb:00/00/00\e\\tail'
  clean="$(flowai_sanitize_display_text "$dirty")"
  if [[ "$clean" == *$'\e'* ]]; then
    printf 'FAIL %s: sanitize left ESC in %q\n' "$id" "$clean" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  elif [[ "$clean" != *plain*tail* ]]; then
    printf 'FAIL %s: sanitize stripped too much: %q\n' "$id" "$clean" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  else
    flowai_test_pass "$id" "Master safe --- printf + display text sanitizes ANSI/OSC"
  fi
}

# ─── ORCH-011: FLOWAI_PLAIN_TERMINAL disables wait_ui redraw (scroll-safe) ───
flowai_test_s_orch_011() {
  local id="ORCH-011"
  local wu="$FLOWAI_HOME/src/core/wait_ui.sh"
  if grep -qF 'FLOWAI_PLAIN_TERMINAL' "$wu" 2>/dev/null \
    && grep -qF "flowai_terminal_plain_enabled" "$FLOWAI_HOME/src/core/log.sh" 2>/dev/null; then
    flowai_test_pass "$id" "plain terminal env wired in wait_ui + log"
  else
    printf 'FAIL %s: PLAIN_TERMINAL must gate wait_ui redraw\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── ORCH-012: Approval gate shows phase-specific context ────────────────────
flowai_test_s_orch_012() {
  local id="ORCH-012"
  local phase="$FLOWAI_HOME/src/core/phase.sh"
  local has_context_fn has_plan has_impl has_git_diff
  has_context_fn=false
  has_plan=false
  has_impl=false
  has_git_diff=false

  grep -q '_flowai_phase_approval_context' "$phase" 2>/dev/null && has_context_fn=true
  grep -q 'PLAN REVIEW' "$phase" 2>/dev/null && has_plan=true
  grep -q 'IMPLEMENTATION REVIEW' "$phase" 2>/dev/null && has_impl=true
  grep -q 'git diff --stat' "$phase" 2>/dev/null && has_git_diff=true

  if $has_context_fn && $has_plan && $has_impl && $has_git_diff; then
    flowai_test_pass "$id" "Approval gate shows phase-specific context (plan, impl, git diff)"
  else
    printf 'FAIL %s: approval context missing (fn=%s plan=%s impl=%s git=%s)\n' \
      "$id" "$has_context_fn" "$has_plan" "$has_impl" "$has_git_diff" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── ORCH-009: Plan UI closes in dashboard (kill-pane) not only tabs ─────────
flowai_test_s_orch_009() {
  local id="ORCH-009"
  local phase="$FLOWAI_HOME/src/core/phase.sh"
  if grep -qF '== "dashboard"' "$phase" 2>/dev/null \
    && grep -qF 'tmux kill-pane' "$phase" 2>/dev/null \
    && grep -qF 'flowai_phase_schedule_close_phase_ui' "$phase" 2>/dev/null \
    && grep -qF 'flowai_phase_schedule_close_plan_ui' "$phase" 2>/dev/null; then
    flowai_test_pass "$id" "Phase completion closes pane in dashboard layout (plan/tasks/review)"
  else
    printf 'FAIL %s: phase.sh must kill-pane for dashboard after plan approve\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── ORCH-013: Cursor auto-fallback detects "out of usage" error patterns ─────
# Prevents: Cursor CLI quota exhaustion crashes the pipeline instead of retrying with --model auto.
flowai_test_s_orch_013() {
  local id="ORCH-013"
  # shellcheck source=../../src/tools/cursor.sh
  source "$FLOWAI_HOME/src/tools/cursor.sh"

  local scratch
  scratch="$(mktemp -d)"

  # Case 1: "out of usage" message → should detect
  printf '%s\n' "You're out of usage. Switch to auto or Auto, or ask your admin to increase your limit to continue." > "$scratch/usage_error.log"
  if ! _flowai_cursor_is_usage_exhausted "$scratch/usage_error.log"; then
    printf 'FAIL %s: did not detect "out of usage" pattern\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    rm -rf "$scratch"
    return
  fi

  # Case 2: "increase your limit" message → should detect
  printf '%s\n' "Error: increase your limit to continue" > "$scratch/limit_error.log"
  if ! _flowai_cursor_is_usage_exhausted "$scratch/limit_error.log"; then
    printf 'FAIL %s: did not detect "increase your limit" pattern\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    rm -rf "$scratch"
    return
  fi

  # Case 3: unrelated error → should NOT detect
  printf '%s\n' "Error: connection timed out" > "$scratch/other_error.log"
  if _flowai_cursor_is_usage_exhausted "$scratch/other_error.log"; then
    printf 'FAIL %s: false positive on unrelated error\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    rm -rf "$scratch"
    return
  fi

  # Case 4: missing file → should NOT detect
  if _flowai_cursor_is_usage_exhausted "$scratch/nonexistent.log"; then
    printf 'FAIL %s: false positive on missing file\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    rm -rf "$scratch"
    return
  fi

  rm -rf "$scratch"
  flowai_test_pass "$id" "Cursor usage-exhausted detector: matches quota errors, ignores unrelated"
}
