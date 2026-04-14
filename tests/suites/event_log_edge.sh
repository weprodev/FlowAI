#!/usr/bin/env bash
# FlowAI test suite — event log edge cases
# Tests for boundary conditions, special characters, missing data, and
# directory auto-creation in the event log subsystem.
# shellcheck shell=bash
#
# Isolated temp projects use: env FLOWAI_DIR=… FLOWAI_HOME=… bash -s <<'EOS' … EOS
# so ShellCheck does not treat exports as lost subshell assignments (SC2030/SC2031).

source "$FLOWAI_HOME/src/core/log.sh"

# ─── EVTE-001: Event emit with special characters in detail ────────────────
flowai_test_s_evte_001() {
  local id="EVTE-001"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_emit "plan" "started" "has \"double quotes\" and \\backslashes\\ and
a newline"
EOS
  if [[ -f "$scratch/.flowai/events.jsonl" ]]; then
    local line
    line="$(head -1 "$scratch/.flowai/events.jsonl")"
    if printf '%s' "$line" | jq -e '.phase == "plan" and .event == "started" and (.detail | length > 0)' >/dev/null 2>&1; then
      flowai_test_pass "$id" "Event emit with special characters produces valid JSONL"
    else
      printf 'FAIL %s: JSONL line failed jq parse or field check: %s\n' "$id" "$line" >&2
      FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    fi
  else
    printf 'FAIL %s: events.jsonl not created\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── EVTE-002: Event tail with fewer events than requested ─────────────────
flowai_test_s_evte_002() {
  local id="EVTE-002"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_emit "spec" "started" ""
flowai_event_emit "spec" "approved" ""
EOS
  local output
  output="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_tail 10
EOS
)"
  local count
  count="$(printf '%s\n' "$output" | grep -c '.')"
  if [[ "$count" -eq 2 ]]; then
    flowai_test_pass "$id" "Event tail with fewer events than requested returns exact count"
  else
    printf 'FAIL %s: expected 2 lines, got %s\n' "$id" "$count" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── EVTE-003: Event recent_for_phase with no matching phase ──────────────
flowai_test_s_evte_003() {
  local id="EVTE-003"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_emit "plan" "started" ""
flowai_event_emit "spec" "approved" ""
EOS
  local output
  output="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_recent_for_phase "review"
EOS
)"
  local count
  count="$(printf '%s' "$output" | grep -c '.' 2>/dev/null || true)"
  count="${count:-0}"
  if [[ "$count" -eq 0 ]]; then
    flowai_test_pass "$id" "Event recent_for_phase with no matching phase returns empty"
  else
    printf 'FAIL %s: expected 0 lines, got %s\n' "$id" "$count" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── EVTE-004: Event latest with no matching event type ────────────────────
flowai_test_s_evte_004() {
  local id="EVTE-004"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_emit "spec" "started" ""
flowai_event_emit "plan" "started" ""
EOS
  local output
  output="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_latest "pipeline_complete"
EOS
)"
  local count
  count="$(printf '%s' "$output" | grep -c '.' 2>/dev/null || true)"
  count="${count:-0}"
  if [[ "$count" -eq 0 ]]; then
    flowai_test_pass "$id" "Event latest with no matching event type returns empty"
  else
    printf 'FAIL %s: expected empty output, got %s lines\n' "$id" "$count" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── EVTE-005: Pipeline status with duplicate events for same phase ────────
flowai_test_s_evte_005() {
  local id="EVTE-005"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_emit "spec" "started" ""
flowai_event_emit "spec" "approved" ""
flowai_event_emit "spec" "phase_complete" ""
EOS
  local status
  status="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_pipeline_status
EOS
)"
  local spec_status
  spec_status="$(printf '%s' "$status" | jq -r '.spec // empty' 2>/dev/null)"
  if [[ "$spec_status" == "phase_complete" ]]; then
    flowai_test_pass "$id" "Pipeline status shows latest event for phase (latest wins)"
  else
    printf 'FAIL %s: expected spec=phase_complete, got spec=%s (full: %s)\n' "$id" "$spec_status" "$status" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── EVTE-006: Event emit creates parent directory if missing ──────────────
flowai_test_s_evte_006() {
  local id="EVTE-006"
  local scratch
  scratch="$(mktemp -d)"
  # Intentionally do NOT create $scratch/.flowai — the emit should create it
  local deep_dir="$scratch/nested/deep/.flowai"
  env FLOWAI_DIR="$deep_dir" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_emit "plan" "started" "auto-created dir"
EOS
  if [[ -f "$deep_dir/events.jsonl" ]]; then
    local line
    line="$(head -1 "$deep_dir/events.jsonl")"
    if printf '%s' "$line" | jq -e '.phase == "plan"' >/dev/null 2>&1; then
      flowai_test_pass "$id" "Event emit creates parent directory if missing"
    else
      printf 'FAIL %s: file created but content invalid: %s\n' "$id" "$line" >&2
      FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    fi
  else
    printf 'FAIL %s: events.jsonl not created at %s\n' "$id" "$deep_dir/events.jsonl" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}
