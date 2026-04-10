#!/usr/bin/env bash
# FlowAI test suite — phase signal coordination
# Tests the signal protocol, role resolution, and prompt composition.
# shellcheck shell=bash

source "$FLOWAI_HOME/src/core/log.sh"

# ─── SIG-001: phase_wait_for returns immediately if signal exists ────────────
flowai_test_s_sig_001() {
  local id="SIG-001"
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.flowai/signals"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"},"pipeline":{"plan":"team-lead"}}' > "$tmp/.flowai/config.json"
  touch "$tmp/.flowai/signals/spec.ready"
  (
    export FLOWAI_DIR="$tmp/.flowai"
    export FLOWAI_HOME
    export SIGNALS_DIR="$tmp/.flowai/signals"
    source "$FLOWAI_HOME/src/core/phase.sh"
    flowai_phase_wait_for "spec" "test-phase"
  )
  local rc=$?
  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "phase_wait_for returns 0 when signal exists"
  else
    printf 'FAIL %s: expected rc=0, got %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$tmp"
}

# ─── SIG-002: phase_wait_for times out correctly ────────────────────────────
flowai_test_s_sig_002() {
  local id="SIG-002"
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.flowai/signals"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$tmp/.flowai/config.json"
  local rc=0
  (
    export FLOWAI_DIR="$tmp/.flowai"
    export FLOWAI_HOME
    export SIGNALS_DIR="$tmp/.flowai/signals"
    export FLOWAI_PHASE_TIMEOUT_SEC=2
    source "$FLOWAI_HOME/src/core/phase.sh"
    flowai_phase_wait_for "nonexistent" "test-phase" 2>/dev/null
  ) || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    flowai_test_pass "$id" "phase_wait_for times out correctly"
  else
    printf 'FAIL %s: expected non-zero rc on timeout, got %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$tmp"
}

# ─── SIG-003: Role prompt resolution finds bundled role ──────────────────────
flowai_test_s_sig_003() {
  local id="SIG-003"
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.flowai"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"},"pipeline":{"plan":"team-lead"}}' > "$tmp/.flowai/config.json"
  (
    export FLOWAI_DIR="$tmp/.flowai"
    export FLOWAI_HOME
    export SIGNALS_DIR="$tmp/.flowai/signals"
    source "$FLOWAI_HOME/src/core/phase.sh"
    local result
    result="$(flowai_phase_resolve_role_prompt "plan")"
    if [[ "$result" == *"src/roles/team-lead.md" ]]; then
      flowai_test_pass "$id" "Role resolution finds bundled team-lead role"
    else
      printf 'FAIL %s: expected team-lead.md, got %s\n' "$id" "$result" >&2
      FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    fi
  )
  rm -rf "$tmp"
}

# ─── SIG-004: Role prompt resolution uses phase override when present ────────
flowai_test_s_sig_004() {
  local id="SIG-004"
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.flowai/roles"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"},"pipeline":{"plan":"team-lead"}}' > "$tmp/.flowai/config.json"
  printf '# Custom plan role\n' > "$tmp/.flowai/roles/plan.md"
  (
    export FLOWAI_DIR="$tmp/.flowai"
    export FLOWAI_HOME
    export SIGNALS_DIR="$tmp/.flowai/signals"
    source "$FLOWAI_HOME/src/core/phase.sh"
    local result
    result="$(flowai_phase_resolve_role_prompt "plan")"
    if [[ "$result" == "$tmp/.flowai/roles/plan.md" ]]; then
      flowai_test_pass "$id" "Role resolution uses phase-level override"
    else
      printf 'FAIL %s: expected phase override, got %s\n' "$id" "$result" >&2
      FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    fi
  )
  rm -rf "$tmp"
}

# ─── SIG-005: Prompt composition includes role + directive ───────────────────
flowai_test_s_sig_005() {
  local id="SIG-005"
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.flowai/launch"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$tmp/.flowai/config.json"
  local role_file="$FLOWAI_HOME/src/roles/backend-engineer.md"
  (
    export FLOWAI_DIR="$tmp/.flowai"
    export FLOWAI_HOME
    export SIGNALS_DIR="$tmp/.flowai/signals"
    source "$FLOWAI_HOME/src/core/phase.sh"
    local result
    result="$(flowai_phase_write_prompt "test" "$role_file" "TEST DIRECTIVE")"
    if [[ -f "$result" ]]; then
      local content
      content="$(cat "$result")"
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
  )
  rm -rf "$tmp"
}

# ─── SIG-006: phase_wait_for fast path does not emit waiting event ───────────
flowai_test_s_sig_006() {
  local id="SIG-006"
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.flowai/signals"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$tmp/.flowai/config.json"
  touch "$tmp/.flowai/signals/spec.ready"
  (
    export FLOWAI_DIR="$tmp/.flowai"
    export FLOWAI_HOME
    export SIGNALS_DIR="$tmp/.flowai/signals"
    source "$FLOWAI_HOME/src/core/phase.sh"
    flowai_phase_wait_for "spec" "test-phase" 2>/dev/null
  )
  # Contract: when signal is already ready, wait_for returns immediately
  # without emitting a "waiting" event. Either no events file exists, or
  # it must not contain a "waiting" event for our phase.
  if [[ -f "$tmp/.flowai/events.jsonl" ]] && \
     grep -q '"event":"waiting"' "$tmp/.flowai/events.jsonl" 2>/dev/null; then
    printf 'FAIL %s: waiting event should not be emitted on fast path\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  else
    flowai_test_pass "$id" "No event emitted when signal already ready (fast path)"
  fi
  rm -rf "$tmp"
}
