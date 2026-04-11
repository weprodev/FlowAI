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
