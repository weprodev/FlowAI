#!/usr/bin/env bash
# FlowAI test suite — phase UX improvements
# Tests for: Claude gum fallback, artifact status update, dynamic pane sizing,
# and plan directive downstream constraints.
# shellcheck shell=bash

# shellcheck source=../../src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"

# ─── PUX-001: _flowai_should_use_gum returns 1 when FLOWAI_PHASE_TOOL=claude ──
flowai_test_s_pux_001() {
  local id="PUX-001"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/signals"
  printf '{"master":{"tool":"claude","model":"claude-sonnet-4-20250514"}}' > "$scratch/.flowai/config.json"

  local rc=0
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" FLOWAI_PHASE_TOOL="claude" \
    bash -s 2>/dev/null <<'EOS' || rc=$?
source "$FLOWAI_HOME/src/core/phase.sh"
# Plugin declares flowai_tool_claude_supports_gum → gum disabled for claude
source "$FLOWAI_HOME/src/tools/claude.sh"
if _flowai_should_use_gum; then
  exit 1  # gum should NOT be used for claude
fi
exit 0
EOS

  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "_flowai_should_use_gum returns false for Claude tool"
  else
    printf 'FAIL %s: _flowai_should_use_gum should return 1 for claude\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── PUX-002: _flowai_should_use_gum returns 0 for non-claude tools ──────────
flowai_test_s_pux_002() {
  local id="PUX-002"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/signals"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$scratch/.flowai/config.json"

  # Only test if gum is installed
  if ! command -v gum >/dev/null 2>&1; then
    flowai_test_pass "$id" "_flowai_should_use_gum for gemini (skipped: gum not installed)"
    rm -rf "$scratch"
    return 0
  fi

  local rc=0
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" FLOWAI_PHASE_TOOL="gemini" \
    bash -s 2>/dev/null <<'EOS' || rc=$?
source "$FLOWAI_HOME/src/core/phase.sh"
if _flowai_should_use_gum; then
  exit 0  # gum SHOULD be used for gemini
fi
exit 1
EOS

  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "_flowai_should_use_gum returns true for Gemini tool"
  else
    printf 'FAIL %s: _flowai_should_use_gum should return 0 for gemini\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── PUX-003: phase.sh approval uses _flowai_should_use_gum (not raw gum check) ─
flowai_test_s_pux_003() {
  local id="PUX-003"
  local phase_sh="$FLOWAI_HOME/src/core/phase.sh"

  # The approval flow must call _flowai_should_use_gum, not raw "command -v gum"
  local has_helper=false
  grep -q '_flowai_should_use_gum' "$phase_sh" 2>/dev/null && has_helper=true

  # Ensure _flowai_should_use_gum checks FLOWAI_PHASE_TOOL
  local checks_tool=false
  grep -q 'FLOWAI_PHASE_TOOL' "$phase_sh" 2>/dev/null && checks_tool=true

  if $has_helper && $checks_tool; then
    flowai_test_pass "$id" "Approval flow uses _flowai_should_use_gum with tool check"
  else
    printf 'FAIL %s: phase.sh must use _flowai_should_use_gum (helper=%s tool=%s)\n' \
      "$id" "$has_helper" "$checks_tool" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── PUX-004: ai.sh exports FLOWAI_PHASE_TOOL ────────────────────────────────
flowai_test_s_pux_004() {
  local id="PUX-004"
  local ai_sh="$FLOWAI_HOME/src/core/ai.sh"

  if grep -q 'export FLOWAI_PHASE_TOOL' "$ai_sh" 2>/dev/null; then
    flowai_test_pass "$id" "ai.sh exports FLOWAI_PHASE_TOOL for downstream gum decisions"
  else
    printf 'FAIL %s: ai.sh must export FLOWAI_PHASE_TOOL\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── PUX-005: _flowai_phase_update_artifact_status patches DRAFT → APPROVED ──
flowai_test_s_pux_005() {
  local id="PUX-005"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/signals"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$scratch/.flowai/config.json"

  local spec_file="$scratch/spec.md"
  cat > "$spec_file" <<'MD'
# Feature Spec

**Specification Status:** DRAFT
**Next Step:** Await user approval to proceed to Plan phase

## Overview
Some content here.
MD

  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" \
    bash -s "$spec_file" 2>/dev/null <<'EOS'
source "$FLOWAI_HOME/src/core/phase.sh"
_flowai_phase_update_artifact_status "$1" "spec"
EOS

  local content
  content="$(cat "$spec_file")"

  local ok=true
  if [[ "$content" == *"APPROVED"* ]]; then
    : # good
  else
    printf 'FAIL %s: status not updated to APPROVED\n' "$id" >&2
    ok=false
  fi
  if [[ "$content" == *"DRAFT"* ]]; then
    printf 'FAIL %s: DRAFT still present after approval\n' "$id" >&2
    ok=false
  fi
  if [[ "$content" == *"Proceed to Plan phase"* ]]; then
    : # good
  else
    printf 'FAIL %s: Next Step not updated\n' "$id" >&2
    ok=false
  fi

  if $ok; then
    flowai_test_pass "$id" "Artifact status updated: DRAFT→APPROVED, Next Step updated"
  else
    printf -- '--- file content ---\n%s\n' "$content" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── PUX-006: _flowai_phase_update_artifact_status handles plan phase ────────
flowai_test_s_pux_006() {
  local id="PUX-006"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/signals"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$scratch/.flowai/config.json"

  local plan_file="$scratch/plan.md"
  cat > "$plan_file" <<'MD'
# Architecture Plan

**Plan Status:** DRAFT
**Next Step:** Await user approval to proceed to implementation

## Architecture
Content here.
MD

  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" \
    bash -s "$plan_file" 2>/dev/null <<'EOS'
source "$FLOWAI_HOME/src/core/phase.sh"
_flowai_phase_update_artifact_status "$1" "plan"
EOS

  local content
  content="$(cat "$plan_file")"

  if [[ "$content" == *"APPROVED"* ]] && [[ "$content" != *"DRAFT"* ]] && [[ "$content" == *"Proceed to Tasks phase"* ]]; then
    flowai_test_pass "$id" "Plan artifact status updated correctly"
  else
    printf 'FAIL %s: plan status update failed\n' "$id" >&2
    printf -- '--- file content ---\n%s\n' "$content" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── PUX-007: Status update is no-op when file has no status markers ─────────
flowai_test_s_pux_007() {
  local id="PUX-007"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/signals"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$scratch/.flowai/config.json"

  local plain_file="$scratch/plain.md"
  printf '# Simple Plan\n\nNo status markers here.\n' > "$plain_file"

  local before
  before="$(cat "$plain_file")"

  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" \
    bash -s "$plain_file" 2>/dev/null <<'EOS'
source "$FLOWAI_HOME/src/core/phase.sh"
_flowai_phase_update_artifact_status "$1" "plan"
EOS

  local after
  after="$(cat "$plain_file")"

  if [[ "$before" == "$after" ]]; then
    flowai_test_pass "$id" "Status update is no-op when no markers present"
  else
    printf 'FAIL %s: file was modified without status markers\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── PUX-008: _flowai_phase_is_active correctly detects active plan ──────────
flowai_test_s_pux_008() {
  local id="PUX-008"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/signals"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$scratch/.flowai/config.json"

  # spec.ready exists (upstream done) but plan.ready does not (plan active)
  touch "$scratch/.flowai/signals/spec.ready"

  local rc=0
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" \
    SIGNALS_DIR="$scratch/.flowai/signals" \
    bash -s 2>/dev/null <<'EOS' || rc=$?
source "$FLOWAI_HOME/src/core/phase.sh"
if _flowai_phase_is_active "plan"; then
  exit 0
fi
exit 1
EOS

  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "Plan detected as active (spec.ready exists, plan.ready absent)"
  else
    printf 'FAIL %s: plan should be active\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── PUX-009: _flowai_phase_is_active returns false when phase is waiting ────
flowai_test_s_pux_009() {
  local id="PUX-009"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/signals"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$scratch/.flowai/config.json"

  # No spec.ready — plan is still waiting for upstream
  local rc=0
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" \
    SIGNALS_DIR="$scratch/.flowai/signals" \
    bash -s 2>/dev/null <<'EOS' || rc=$?
source "$FLOWAI_HOME/src/core/phase.sh"
if _flowai_phase_is_active "plan"; then
  exit 1  # should NOT be active
fi
exit 0
EOS

  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "Plan not active when upstream signal absent"
  else
    printf 'FAIL %s: plan should not be active without spec.ready\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── PUX-010: _flowai_phase_is_active returns false when phase is completed ──
flowai_test_s_pux_010() {
  local id="PUX-010"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/signals"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$scratch/.flowai/config.json"

  # Both signals exist — plan is complete
  touch "$scratch/.flowai/signals/spec.ready"
  touch "$scratch/.flowai/signals/plan.ready"

  local rc=0
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" \
    SIGNALS_DIR="$scratch/.flowai/signals" \
    bash -s 2>/dev/null <<'EOS' || rc=$?
source "$FLOWAI_HOME/src/core/phase.sh"
if _flowai_phase_is_active "plan"; then
  exit 1  # should NOT be active — it's completed
fi
exit 0
EOS

  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "Plan not active when own completion signal exists"
  else
    printf 'FAIL %s: plan should not be active when plan.ready exists\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── PUX-011: Both impl and review detected as active simultaneously ────────
flowai_test_s_pux_011() {
  local id="PUX-011"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/signals"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$scratch/.flowai/config.json"

  # impl active: tasks.master_approved.ready exists, impl.code_complete.ready absent
  # review active: impl.code_complete.ready exists, review.ready absent
  # This simulates impl revision cycle where both are running
  touch "$scratch/.flowai/signals/spec.ready"
  touch "$scratch/.flowai/signals/plan.ready"
  touch "$scratch/.flowai/signals/tasks.master_approved.ready"
  touch "$scratch/.flowai/signals/impl.code_complete.ready"

  local rc=0
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" \
    SIGNALS_DIR="$scratch/.flowai/signals" \
    bash -s 2>/dev/null <<'EOS' || rc=$?
source "$FLOWAI_HOME/src/core/phase.sh"
impl_active=false
review_active=false
_flowai_phase_is_active "impl" && impl_active=true
_flowai_phase_is_active "review" && review_active=true
# impl should NOT be active (impl.code_complete.ready exists)
# review SHOULD be active (impl.code_complete.ready exists, review.ready absent)
if [[ "$impl_active" == "false" ]] && [[ "$review_active" == "true" ]]; then
  exit 0
fi
printf 'impl_active=%s review_active=%s\n' "$impl_active" "$review_active" >&2
exit 1
EOS

  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "Correct active detection: impl complete, review active"
  else
    printf 'FAIL %s: active detection mismatch for impl/review\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── PUX-012: _flowai_phase_name_from_title extracts phase name correctly ────
flowai_test_s_pux_012() {
  local id="PUX-012"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/signals"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$scratch/.flowai/config.json"

  local rc=0
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" \
    bash -s 2>/dev/null <<'EOS' || rc=$?
source "$FLOWAI_HOME/src/core/phase.sh"
t1="$(_flowai_phase_name_from_title '🤖 Phase: plan [gemini: gemini-2.5-pro]')"
t2="$(_flowai_phase_name_from_title '🤖 Phase: impl [claude: claude-sonnet-4-20250514]')"
t3="$(_flowai_phase_name_from_title '👑 Master Agent [gemini: gemini-2.5-pro]')"
[[ "$t1" == "plan" ]] || { echo "t1=$t1" >&2; exit 1; }
[[ "$t2" == "impl" ]] || { echo "t2=$t2" >&2; exit 1; }
[[ -z "$t3" ]] || { echo "t3=$t3 (should be empty)" >&2; exit 1; }
exit 0
EOS

  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "Phase name extraction from pane title works correctly"
  else
    printf 'FAIL %s: phase name extraction failed\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── PUX-013: Plan directive includes downstream artifact constraints ────────
flowai_test_s_pux_013() {
  local id="PUX-013"
  local plan_sh="$FLOWAI_HOME/src/phases/plan.sh"

  local has_constraint has_review_only has_no_multiple
  has_constraint=false
  has_review_only=false
  has_no_multiple=false

  grep -q 'DOWNSTREAM ARTIFACT CONSTRAINTS' "$plan_sh" 2>/dev/null && has_constraint=true
  grep -q 'ONLY review.md' "$plan_sh" 2>/dev/null && has_review_only=true
  grep -q 'ARCHITECTURE_REVIEW.md' "$plan_sh" 2>/dev/null && has_no_multiple=true

  if $has_constraint && $has_review_only && $has_no_multiple; then
    flowai_test_pass "$id" "Plan directive includes downstream artifact constraints"
  else
    printf 'FAIL %s: plan.sh missing downstream constraints (section=%s review_only=%s examples=%s)\n' \
      "$id" "$has_constraint" "$has_review_only" "$has_no_multiple" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── PUX-017: Tasks directive includes artifact ownership constraints ────────
flowai_test_s_pux_017() {
  local id="PUX-017"
  local tasks_sh="$FLOWAI_HOME/src/phases/tasks.sh"

  local has_constraint has_review_only has_no_multiple
  has_constraint=false
  has_review_only=false
  has_no_multiple=false

  grep -q 'ARTIFACT OWNERSHIP CONSTRAINTS' "$tasks_sh" 2>/dev/null && has_constraint=true
  grep -q 'review.md ONLY' "$tasks_sh" 2>/dev/null && has_review_only=true
  grep -q 'ARCHITECTURE_REVIEW.md' "$tasks_sh" 2>/dev/null && has_no_multiple=true

  if $has_constraint && $has_review_only && $has_no_multiple; then
    flowai_test_pass "$id" "Tasks directive includes artifact ownership constraints"
  else
    printf 'FAIL %s: tasks.sh missing artifact constraints (section=%s review_only=%s examples=%s)\n' \
      "$id" "$has_constraint" "$has_review_only" "$has_no_multiple" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── PUX-014: master.sh recovery menu uses _flowai_should_use_gum ────────────
flowai_test_s_pux_014() {
  local id="PUX-014"
  local master_sh="$FLOWAI_HOME/src/phases/master.sh"

  if grep -q '_flowai_should_use_gum' "$master_sh" 2>/dev/null; then
    flowai_test_pass "$id" "Master recovery menu uses _flowai_should_use_gum"
  else
    printf 'FAIL %s: master.sh must use _flowai_should_use_gum for recovery menu\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── PUX-015: phase.sh has _flowai_phase_update_artifact_status function ─────
flowai_test_s_pux_015() {
  local id="PUX-015"
  local phase_sh="$FLOWAI_HOME/src/core/phase.sh"

  local has_fn has_approve_call
  has_fn=false
  has_approve_call=false

  grep -q '_flowai_phase_update_artifact_status()' "$phase_sh" 2>/dev/null && has_fn=true
  grep -q '_flowai_phase_update_artifact_status.*target_file' "$phase_sh" 2>/dev/null && has_approve_call=true

  if $has_fn && $has_approve_call; then
    flowai_test_pass "$id" "Artifact status update function exists and is called on approve"
  else
    printf 'FAIL %s: missing status update (fn=%s call=%s)\n' "$id" "$has_fn" "$has_approve_call" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── PUX-016: resize function uses _flowai_phase_is_active ───────────────────
flowai_test_s_pux_016() {
  local id="PUX-016"
  local phase_sh="$FLOWAI_HOME/src/core/phase.sh"

  local has_is_active has_signal_check has_active_waiting
  has_is_active=false
  has_signal_check=false
  has_active_waiting=false

  grep -q '_flowai_phase_is_active' "$phase_sh" 2>/dev/null && has_is_active=true
  grep -q 'spec.ready.*plan.ready' "$phase_sh" 2>/dev/null && has_signal_check=true
  grep -q 'active_pids\|waiting_pids' "$phase_sh" 2>/dev/null && has_active_waiting=true

  if $has_is_active && $has_signal_check && $has_active_waiting; then
    flowai_test_pass "$id" "Resize uses signal-based active/waiting classification"
  else
    printf 'FAIL %s: resize missing active detection (is_active=%s signals=%s arrays=%s)\n' \
      "$id" "$has_is_active" "$has_signal_check" "$has_active_waiting" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── PUX-018: OVER_SCOPE escalates to phase error (not just warning) ────────
flowai_test_s_pux_018() {
  local id="PUX-018"
  local master_sh="$FLOWAI_HOME/src/phases/master.sh"

  # Extract _master_run_scope_check function body and verify it calls
  # flowai_phase_emit_error in the OVER_SCOPE branch (not just log_warn).
  local fn_body
  fn_body="$(sed -n '/_master_run_scope_check()/,/^}/p' "$master_sh")"

  local has_over_scope=false has_emit_error=false
  printf '%s' "$fn_body" | grep -q 'OVER_SCOPE' && has_over_scope=true
  printf '%s' "$fn_body" | grep -q 'flowai_phase_emit_error' && has_emit_error=true

  if $has_over_scope && $has_emit_error; then
    flowai_test_pass "$id" "OVER_SCOPE escalates to phase error (triggers recovery menu)"
  else
    printf 'FAIL %s: _master_run_scope_check must emit phase error on OVER_SCOPE (over_scope=%s emit_error=%s)\n' \
      "$id" "$has_over_scope" "$has_emit_error" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── PUX-022: Review rejection uses one-shot analysis (not interactive Master) ─
flowai_test_s_pux_022() {
  local id="PUX-022"
  local master_sh="$FLOWAI_HOME/src/phases/master.sh"

  # The review rejection block must call flowai_ai_run_oneshot for analysis
  local has_oneshot=false has_user_feedback_event=false has_code_only=false
  grep -q 'flowai_ai_run_oneshot.*review.*_review_analysis_prompt' "$master_sh" 2>/dev/null && has_oneshot=true
  grep -q 'user_revision_feedback' "$master_sh" 2>/dev/null && has_user_feedback_event=true
  grep -q 'Code Revision Required\|CODE changes only' "$master_sh" 2>/dev/null && has_code_only=true

  if $has_oneshot && $has_user_feedback_event && $has_code_only; then
    flowai_test_pass "$id" "Review rejection uses one-shot analysis + logs user feedback"
  else
    printf 'FAIL %s: review rejection (oneshot=%s feedback_event=%s code_only=%s)\n' \
      "$id" "$has_oneshot" "$has_user_feedback_event" "$has_code_only" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── PUX-023: Impl has user approval gate after revision ────────────────────
flowai_test_s_pux_023() {
  local id="PUX-023"
  local impl_sh="$FLOWAI_HOME/src/phases/implement.sh"

  # After revision re-run, impl must call flowai_phase_verify_artifact before code_complete
  local has_verify=false has_revised_label=false
  grep -q 'flowai_phase_verify_artifact.*Revised Implementation' "$impl_sh" 2>/dev/null && has_verify=true
  grep -q 'Awaiting your approval before Review re-runs' "$impl_sh" 2>/dev/null && has_revised_label=true

  if $has_verify && $has_revised_label; then
    flowai_test_pass "$id" "Impl has user approval gate after revision (before Review re-runs)"
  else
    printf 'FAIL %s: impl revision approval gate (verify=%s label=%s)\n' \
      "$id" "$has_verify" "$has_revised_label" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── PUX-024: Docs document rejection type separation ───────────────────────
flowai_test_s_pux_024() {
  local id="PUX-024"
  local docs="$FLOWAI_HOME/docs/AGENT-COMMUNICATION.md"

  local has_separation=false has_code_col=false
  grep -q 'Rejection Type Separation' "$docs" 2>/dev/null && has_separation=true
  grep -q 'MD file.*Code' "$docs" 2>/dev/null || grep -q '\*\*Code\*\*' "$docs" 2>/dev/null && has_code_col=true

  if $has_separation && $has_code_col; then
    flowai_test_pass "$id" "Docs document rejection type separation (MD vs Code)"
  else
    printf 'FAIL %s: docs missing rejection separation (section=%s code_col=%s)\n' \
      "$id" "$has_separation" "$has_code_col" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── PUX-019: flowai_phase_is_pane_alive and flowai_phase_respawn exist ──────
flowai_test_s_pux_019() {
  local id="PUX-019"
  local phase_sh="$FLOWAI_HOME/src/core/phase.sh"

  local has_alive=false has_respawn=false
  grep -q 'flowai_phase_is_pane_alive()' "$phase_sh" 2>/dev/null && has_alive=true
  grep -q 'flowai_phase_respawn()' "$phase_sh" 2>/dev/null && has_respawn=true

  if $has_alive && $has_respawn; then
    flowai_test_pass "$id" "Phase pane health check and respawn functions exist"
  else
    printf 'FAIL %s: missing pane management (alive=%s respawn=%s)\n' \
      "$id" "$has_alive" "$has_respawn" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── PUX-020: Review rejection routes to impl (not interactive Master) ───────
flowai_test_s_pux_020() {
  local id="PUX-020"
  local master_sh="$FLOWAI_HOME/src/phases/master.sh"

  # Extract the review rejection block — must write impl.rejection_context
  local has_review_special=false has_impl_rejection=false has_respawn_check=false
  grep -q 'rej_phase.*==.*"review"' "$master_sh" 2>/dev/null && has_review_special=true
  grep -q 'impl.rejection_context' "$master_sh" 2>/dev/null && has_impl_rejection=true
  grep -q 'flowai_phase_is_pane_alive.*impl' "$master_sh" 2>/dev/null && has_respawn_check=true

  if $has_review_special && $has_impl_rejection && $has_respawn_check; then
    flowai_test_pass "$id" "Review rejection routes to Implement with pane health check"
  else
    printf 'FAIL %s: review rejection handling (special=%s impl_ctx=%s respawn=%s)\n' \
      "$id" "$has_review_special" "$has_impl_rejection" "$has_respawn_check" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── PUX-021: Post-QA paths check impl pane alive before sending revision ────
flowai_test_s_pux_021() {
  local id="PUX-021"
  local master_sh="$FLOWAI_HOME/src/phases/master.sh"

  # Count occurrences of flowai_phase_is_pane_alive "impl" — should be at least 3
  # (NEEDS_FOLLOW_UP path, user rejection path, review rejection path)
  local count
  count="$(grep -c 'flowai_phase_is_pane_alive.*impl' "$master_sh" 2>/dev/null || echo 0)"

  if [[ "$count" -ge 3 ]]; then
    flowai_test_pass "$id" "All impl revision paths check pane health ($count checks)"
  else
    printf 'FAIL %s: expected >=3 impl pane health checks, found %s\n' "$id" "$count" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}
