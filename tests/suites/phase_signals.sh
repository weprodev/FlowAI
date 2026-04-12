#!/usr/bin/env bash
# FlowAI test suite — phase signal coordination
# Tests the signal protocol, role resolution, and prompt composition.
# shellcheck shell=bash
#
# Temp projects: env FLOWAI_DIR=… bash -s <<'EOS' … EOS (avoids SC2030/SC2031 on export-in-subshell).

source "$FLOWAI_HOME/src/core/log.sh"

# ─── SIG-001: phase_wait_for returns immediately if signal exists ────────────
flowai_test_s_sig_001() {
  local id="SIG-001"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/signals"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"},"pipeline":{"plan":"team-lead"}}' > "$scratch/.flowai/config.json"
  touch "$scratch/.flowai/signals/spec.ready"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/phase.sh"
flowai_phase_wait_for "spec" "test-phase"
EOS
  local rc=$?
  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "phase_wait_for returns 0 when signal exists"
  else
    printf 'FAIL %s: expected rc=0, got %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── SIG-002: phase_wait_for times out correctly ────────────────────────────
flowai_test_s_sig_002() {
  local id="SIG-002"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/signals"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$scratch/.flowai/config.json"
  local rc=0
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" FLOWAI_PHASE_TIMEOUT_SEC=2 \
    bash -s 2>/dev/null <<'EOS' || rc=$?
source "$FLOWAI_HOME/src/core/phase.sh"
flowai_phase_wait_for "nonexistent" "test-phase"
EOS
  if [[ "$rc" -ne 0 ]]; then
    flowai_test_pass "$id" "phase_wait_for times out correctly"
  else
    printf 'FAIL %s: expected non-zero rc on timeout, got %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── SIG-003: Role prompt resolution finds bundled role ──────────────────────
flowai_test_s_sig_003() {
  local id="SIG-003"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"},"pipeline":{"plan":"team-lead"}}' > "$scratch/.flowai/config.json"
  local result
  result="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/phase.sh"
flowai_phase_resolve_role_prompt "plan"
EOS
)"
  if [[ "$result" == *"src/roles/team-lead.md" ]]; then
    flowai_test_pass "$id" "Role resolution finds bundled team-lead role"
  else
    printf 'FAIL %s: expected team-lead.md, got %s\n' "$id" "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── SIG-004: Role prompt resolution uses phase override when present ────────
flowai_test_s_sig_004() {
  local id="SIG-004"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/roles"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"},"pipeline":{"plan":"team-lead"}}' > "$scratch/.flowai/config.json"
  printf '# Custom plan role\n' > "$scratch/.flowai/roles/plan.md"
  local result
  result="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/phase.sh"
flowai_phase_resolve_role_prompt "plan"
EOS
)"
  if [[ "$result" == "$scratch/.flowai/roles/plan.md" ]]; then
    flowai_test_pass "$id" "Role resolution uses phase-level override"
  else
    printf 'FAIL %s: expected phase override, got %s\n' "$id" "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── SIG-005: Prompt composition includes role + directive ───────────────────
flowai_test_s_sig_005() {
  local id="SIG-005"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/launch"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$scratch/.flowai/config.json"
  local role_file="$FLOWAI_HOME/src/roles/backend-engineer.md"
  local prompt_file content
  prompt_file="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<EOF
source "\$FLOWAI_HOME/src/core/phase.sh"
flowai_phase_write_prompt "test" "$role_file" "TEST DIRECTIVE"
EOF
)"
  if [[ -f "$prompt_file" ]]; then
    content="$(cat "$prompt_file")"
    if [[ "$content" == *"TEST DIRECTIVE"* ]]; then
      flowai_test_pass "$id" "Prompt composition includes directive"
    else
      printf 'FAIL %s: prompt missing directive\n' "$id" >&2
      FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    fi
  else
    printf 'FAIL %s: prompt file not created\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── SIG-006: phase_wait_for fast path does not emit waiting event ───────────
flowai_test_s_sig_006() {
  local id="SIG-006"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/signals"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$scratch/.flowai/config.json"
  touch "$scratch/.flowai/signals/spec.ready"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s 2>/dev/null <<'EOS'
source "$FLOWAI_HOME/src/core/phase.sh"
flowai_phase_wait_for "spec" "test-phase"
EOS
  # Contract: when signal is already ready, wait_for returns immediately
  # without emitting a "waiting" event. Either no events file exists, or
  # it must not contain a "waiting" event for our phase.
  if [[ -f "$scratch/.flowai/events.jsonl" ]] && \
     grep -q '"event":"waiting"' "$scratch/.flowai/events.jsonl" 2>/dev/null; then
    printf 'FAIL %s: waiting event should not be emitted on fast path\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  else
    flowai_test_pass "$id" "No event emitted when signal already ready (fast path)"
  fi
  rm -rf "$scratch"
}

# ─── SIG-007: PIPELINE COORDINATION block is always present in composed prompt ─
# This is the architectural invariant: every agent sees the pipeline rules
# regardless of role, skill, or tool. This test calls flowai_skills_build_prompt
# directly and asserts [PIPELINE COORDINATION] is present in the output.
flowai_test_s_sig_007() {
  local id="SIG-007"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/launch"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$scratch/.flowai/config.json"

  # Create a minimal role+directive prompt file (simulates flowai_phase_write_prompt output)
  local prompt_file="$scratch/.flowai/launch/test_prompt.md"
  printf '# Minimal Role\nYou are a test agent.\n\nTEST DIRECTIVE\n' > "$prompt_file"

  # Call flowai_skills_build_prompt and capture the full composed prompt
  local composed
  composed="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" PWD="$scratch" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/config.sh"
source "$FLOWAI_HOME/src/core/skills.sh"
source "$FLOWAI_HOME/src/core/eventlog.sh"
source "$FLOWAI_HOME/src/core/graph.sh" 2>/dev/null || true
flowai_skills_build_prompt "plan" "$FLOWAI_DIR/launch/test_prompt.md"
EOS
)"

  if [[ "$composed" == *"[PIPELINE COORDINATION]"* ]]; then
    flowai_test_pass "$id" "PIPELINE COORDINATION block injected in composed prompt"
  else
    printf 'FAIL %s: [PIPELINE COORDINATION] block missing from composed prompt\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── SIG-008: master.sh requires user_approved marker before spec.ready ──────
# Spec approval must be explicit (marker file), NOT auto on spec.md existence.
flowai_test_s_sig_008() {
  local id="SIG-008"
  local plugin="$FLOWAI_HOME/src/phases/master.sh"

  # The watcher must check for BOTH spec.md AND spec.user_approved
  if grep -q 'spec.user_approved' "$plugin" 2>/dev/null; then
    # It must NOT have the old auto-approve pattern (spec.md only)
    if grep -Fq "auto-approved" "$plugin" 2>/dev/null; then
      printf 'FAIL %s: master.sh still has auto-approve logic\n' "$id" >&2
      FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    else
      flowai_test_pass "$id" "Spec approval requires user_approved marker (not auto)"
    fi
  else
    printf 'FAIL %s: master.sh does not reference spec.user_approved marker\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── SIG-009: tasks.sh emits tasks_produced and waits for master approval ────
# Tasks must NOT use flowai_phase_run_loop (which has a human gum gate).
# Instead it emits tasks_produced and waits for tasks.master_approved.
flowai_test_s_sig_009() {
  local id="SIG-009"
  local plugin="$FLOWAI_HOME/src/phases/tasks.sh"

  local has_event has_master_signal has_no_run_loop
  has_event=false
  has_master_signal=false
  has_no_run_loop=true

  grep -q 'tasks_produced' "$plugin" 2>/dev/null && has_event=true
  grep -q 'tasks.master_approved' "$plugin" 2>/dev/null && has_master_signal=true
  grep -q 'flowai_phase_run_loop' "$plugin" 2>/dev/null && has_no_run_loop=false

  if $has_event && $has_master_signal && $has_no_run_loop; then
    flowai_test_pass "$id" "Tasks uses Master approval (no human gum gate)"
  else
    printf 'FAIL %s: tasks.sh contract broken (event=%s master_signal=%s no_run_loop=%s)\n' \
      "$id" "$has_event" "$has_master_signal" "$has_no_run_loop" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}
