#!/usr/bin/env bash
# FlowAI test suite — event log (shared message bus)
# Tests for pipeline event persistence, filtering, and summarization.
# shellcheck shell=bash
#
# Isolated temp projects use: env FLOWAI_DIR=… FLOWAI_HOME=… bash -s <<'EOS' … EOS
# so ShellCheck does not treat exports as lost subshell assignments (SC2030/SC2031).

source "$FLOWAI_HOME/src/core/log.sh"

# ─── EVT-001: Event emit creates file and writes valid JSONL ─────────────────
flowai_test_s_evt_001() {
  local id="EVT-001"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_emit "plan" "started" "test detail"
EOS
  if [[ -f "$scratch/.flowai/events.jsonl" ]]; then
    local line
    line="$(head -1 "$scratch/.flowai/events.jsonl")"
    if printf '%s' "$line" | jq -e '.phase == "plan" and .event == "started"' >/dev/null 2>&1; then
      flowai_test_pass "$id" "Event emit creates valid JSONL"
    else
      printf 'FAIL %s: invalid JSON in event log: %s\n' "$id" "$line" >&2
      FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    fi
  else
    printf 'FAIL %s: events.jsonl not created\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── EVT-002: Event tail returns correct number of lines ─────────────────────
flowai_test_s_evt_002() {
  local id="EVT-002"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_emit "spec" "started" ""
flowai_event_emit "spec" "approved" ""
flowai_event_emit "plan" "started" ""
EOS
  # Assertions outside subshell so FLOWAI_TEST_FAILURES propagates
  local count
  count="$(FLOWAI_EVENTS_FILE="$scratch/.flowai/events.jsonl" \
    bash -c 'tail -n 2 "$FLOWAI_EVENTS_FILE" | wc -l | tr -d " "')"
  if [[ "$count" -eq 2 ]]; then
    flowai_test_pass "$id" "Event tail returns correct count"
  else
    printf 'FAIL %s: expected 2 lines, got %s\n' "$id" "$count" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── EVT-003: Event filter by phase works ────────────────────────────────────
flowai_test_s_evt_003() {
  local id="EVT-003"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_emit "spec" "started" ""
flowai_event_emit "plan" "started" ""
flowai_event_emit "spec" "approved" ""
EOS
  local spec_events
  spec_events="$(grep -cF '"phase":"spec"' "$scratch/.flowai/events.jsonl" 2>/dev/null || printf '0')"
  if [[ "$spec_events" -eq 2 ]]; then
    flowai_test_pass "$id" "Event filter by phase returns correct events"
  else
    printf 'FAIL %s: expected 2 spec events, got %s\n' "$id" "$spec_events" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── EVT-004: Event reset clears log and writes init event ──────────────────
flowai_test_s_evt_004() {
  local id="EVT-004"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_emit "spec" "started" ""
flowai_event_emit "plan" "started" ""
flowai_event_reset
EOS
  local count
  count="$(wc -l < "$scratch/.flowai/events.jsonl" | tr -d ' ')"
  if [[ "$count" -eq 1 ]]; then
    local event
    event="$(jq -r '.event' "$scratch/.flowai/events.jsonl" 2>/dev/null | tr -d '\r')"
    if [[ "$event" == "pipeline_initialized" ]]; then
      flowai_test_pass "$id" "Event reset clears log and writes init event"
    else
      printf 'FAIL %s: expected pipeline_initialized, got %s\n' "$id" "$event" >&2
      FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    fi
  else
    printf 'FAIL %s: expected 1 line after reset, got %s\n' "$id" "$count" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── EVT-005: Pipeline status returns JSON with phase states ────────────────
flowai_test_s_evt_005() {
  local id="EVT-005"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_emit "spec" "approved" ""
flowai_event_emit "plan" "started" ""
EOS
  local status
  status="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_pipeline_status
EOS
)"
  local spec_status plan_status
  spec_status="$(printf '%s' "$status" | jq -r '.spec // empty' 2>/dev/null)"
  plan_status="$(printf '%s' "$status" | jq -r '.plan // empty' 2>/dev/null)"
  if [[ "$spec_status" == "approved" && "$plan_status" == "started" ]]; then
    flowai_test_pass "$id" "Pipeline status returns correct phase states"
  else
    printf 'FAIL %s: unexpected status: %s\n' "$id" "$status" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── EVT-006: Format for prompt produces readable output ────────────────────
flowai_test_s_evt_006() {
  local id="EVT-006"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_emit "spec" "approved" "spec.md written"
EOS
  local formatted
  formatted="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_format_for_prompt 5
EOS
)"
  if [[ "$formatted" == *"spec:approved"* ]]; then
    flowai_test_pass "$id" "Format for prompt produces readable output"
  else
    printf 'FAIL %s: formatted output missing expected content: %s\n' "$id" "$formatted" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── EVT-007: Compact deduplicates consecutive same-phase progress ──────────
flowai_test_s_evt_007() {
  local id="EVT-007"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_emit "spec" "approved" ""
flowai_event_emit "impl" "progress" "1/5 tasks"
flowai_event_emit "impl" "progress" "2/5 tasks"
flowai_event_emit "impl" "progress" "3/5 tasks"
flowai_event_emit "plan" "approved" ""
EOS
  local formatted
  formatted="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_format_for_prompt 20
EOS
)"
  # 5 raw events should become 3 lines (3 progress → 1)
  local line_count
  line_count="$(printf '%s\n' "$formatted" | wc -l | tr -d ' ')"
  if [[ "$line_count" -eq 3 ]] && [[ "$formatted" == *"3/5 tasks"* ]] && [[ "$formatted" != *"1/5 tasks"* ]]; then
    flowai_test_pass "$id" "Compact deduplicates consecutive same-phase progress"
  else
    printf 'FAIL %s: expected 3 lines with only last progress, got %d lines: %s\n' "$id" "$line_count" "$formatted" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── EVT-008: Compact preserves cross-phase progress events ─────────────────
flowai_test_s_evt_008() {
  local id="EVT-008"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_emit "impl" "progress" "1/3"
flowai_event_emit "review" "progress" "checking"
flowai_event_emit "impl" "progress" "2/3"
EOS
  local formatted
  formatted="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_format_for_prompt 20
EOS
)"
  # All 3 events should be preserved (different phases break the consecutive run)
  local line_count
  line_count="$(printf '%s\n' "$formatted" | wc -l | tr -d ' ')"
  if [[ "$line_count" -eq 3 ]]; then
    flowai_test_pass "$id" "Compact preserves cross-phase progress events"
  else
    printf 'FAIL %s: expected 3 lines, got %d: %s\n' "$id" "$line_count" "$formatted" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── EVT-009: Minimal format produces phase:event only ──────────────────────
flowai_test_s_evt_009() {
  local id="EVT-009"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  printf '{"event_log":{"prompt_format":"minimal"}}' > "$scratch/.flowai/config.json"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_emit "spec" "approved" "detail should be stripped"
EOS
  local formatted
  formatted="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_format_for_prompt 5
EOS
)"
  # Minimal: no timestamps, no detail — just "phase:event"
  if [[ "$formatted" == "spec:approved" ]]; then
    flowai_test_pass "$id" "Minimal format produces phase:event only"
  else
    printf 'FAIL %s: expected "spec:approved", got "%s"\n' "$id" "$formatted" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── EVT-010: Full format returns raw JSONL ─────────────────────────────────
flowai_test_s_evt_010() {
  local id="EVT-010"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  printf '{"event_log":{"prompt_format":"full"}}' > "$scratch/.flowai/config.json"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_emit "plan" "started" "full detail"
EOS
  local formatted
  formatted="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_format_for_prompt 5
EOS
)"
  # Full: raw JSON, must be parseable by jq and contain all fields
  if printf '%s' "$formatted" | jq -e '.phase == "plan" and .event == "started" and .detail == "full detail"' >/dev/null 2>&1; then
    flowai_test_pass "$id" "Full format returns raw JSONL"
  else
    printf 'FAIL %s: full format not valid JSONL: %s\n' "$id" "$formatted" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── EVT-011: Unknown prompt_format falls back to compact ──────────────────
flowai_test_s_evt_011() {
  local id="EVT-011"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  printf '{"event_log":{"prompt_format":"nonexistent_format"}}' > "$scratch/.flowai/config.json"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_emit "spec" "approved" "test"
EOS
  local formatted
  formatted="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_format_for_prompt 5
EOS
)"
  # Unknown format falls through to the * case (compact):
  # compact output has short timestamps like "19:31" and "phase:event"
  if [[ "$formatted" == *"spec:approved"* ]] && [[ "$formatted" =~ [0-9]{2}:[0-9]{2} ]]; then
    flowai_test_pass "$id" "Unknown prompt_format falls back to compact"
  else
    printf 'FAIL %s: expected compact output with timestamp, got: %s\n' "$id" "$formatted" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── EVT-012: Empty events file returns empty string for all formats ────────
flowai_test_s_evt_012() {
  local id="EVT-012"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  touch "$scratch/.flowai/events.jsonl"
  local fail=0
  for prompt_fmt in compact minimal full; do
    if [[ "$prompt_fmt" != "compact" ]]; then
      printf '{"event_log":{"prompt_format":"%s"}}' "$prompt_fmt" > "$scratch/.flowai/config.json"
    else
      printf '{}' > "$scratch/.flowai/config.json"
    fi
    local result
    result="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_format_for_prompt 5
EOS
)"
    if [[ -n "$result" ]] && [[ "$result" != $'\n' ]]; then
      printf 'FAIL %s: %s format returned non-empty for empty file: [%s]\n' "$id" "$prompt_fmt" "$result" >&2
      fail=1
    fi
  done
  if [[ "$fail" -eq 0 ]]; then
    flowai_test_pass "$id" "Empty events file returns empty string for all formats"
  else
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}
