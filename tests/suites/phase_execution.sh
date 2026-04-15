#!/usr/bin/env bash
# Phase execution tests — emit_error, artifact_boundary, write_prompt,
# role resolution tiers, session_prompt_end, and phase_focus no-op.
# shellcheck shell=bash
# shellcheck disable=SC2016  # bash -c strings use $ vars for inner shell, not outer

# shellcheck source=../../src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"

# ─── PHE-001: flowai_phase_emit_error creates valid error event ───────────────
flowai_test_s_phe_001() {
  local id="PHE-001"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  printf '{}' > "$scratch/.flowai/config.json"
  local _fh="$FLOWAI_HOME"
  local rc=0
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$_fh" \
    bash -c '
      source "$FLOWAI_HOME/src/core/phase.sh"
      flowai_phase_emit_error "plan" "something broke"
    ' 2>/dev/null || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    printf 'FAIL %s: emit_error exited with rc=%s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    rm -rf "$scratch"
    return
  fi
  if [[ ! -f "$scratch/.flowai/events.jsonl" ]]; then
    printf 'FAIL %s: events.jsonl not created\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    rm -rf "$scratch"
    return
  fi
  local last_line
  last_line="$(tail -1 "$scratch/.flowai/events.jsonl")"
  if [[ "$last_line" == *'"phase":"plan"'* ]] && [[ "$last_line" == *'"event":"error"'* ]] && [[ "$last_line" == *'"detail":"something broke"'* ]]; then
    flowai_test_pass "$id" "emit_error creates valid error event in events.jsonl"
  else
    printf 'FAIL %s: event line does not match expected fields: %s\n' "$id" "$last_line" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── PHE-002: artifact_boundary output contains phase name and ownership map ──
flowai_test_s_phe_002() {
  local id="PHE-002"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  printf '{}' > "$scratch/.flowai/config.json"
  local _fh="$FLOWAI_HOME"
  local output
  output="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$_fh" \
    bash -c '
      source "$FLOWAI_HOME/src/core/phase.sh"
      flowai_phase_artifact_boundary "plan"
    ' 2>/dev/null)"
  local ok=true
  if [[ "$output" != *"'plan' phase"* ]]; then
    printf 'FAIL %s: output missing phase name "plan"\n' "$id" >&2
    ok=false
  fi
  if [[ "$output" != *"spec/master"* ]] || [[ "$output" != *"plan.md"* ]] || [[ "$output" != *"tasks.md"* ]]; then
    printf 'FAIL %s: output missing ownership map entries\n' "$id" >&2
    ok=false
  fi
  if $ok; then
    flowai_test_pass "$id" "artifact_boundary contains phase name and ownership map"
  else
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── PHE-003: artifact_boundary with secondary boundary appends extra sentence ─
flowai_test_s_phe_003() {
  local id="PHE-003"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  printf '{}' > "$scratch/.flowai/config.json"
  local _fh="$FLOWAI_HOME"
  local output
  output="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$_fh" \
    bash -c '
      source "$FLOWAI_HOME/src/core/phase.sh"
      flowai_phase_artifact_boundary "review" "When blocking impl, you may ALSO write the rejection file."
    ' 2>/dev/null)"
  if [[ "$output" == *"When blocking impl, you may ALSO write the rejection file."* ]]; then
    flowai_test_pass "$id" "artifact_boundary with secondary appends extra sentence"
  else
    printf 'FAIL %s: secondary boundary text not found in output\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── PHE-004: write_prompt creates file with role+directive+boundary ──────────
flowai_test_s_phe_004() {
  local id="PHE-004"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/launch"
  printf '{}' > "$scratch/.flowai/config.json"
  # Create a small role file
  printf '# Test Role\nYou are a test role.\n' > "$scratch/role.md"
  local _fh="$FLOWAI_HOME"
  local result
  result="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$_fh" \
    bash -c '
      source "$FLOWAI_HOME/src/core/phase.sh"
      flowai_phase_write_prompt "plan" "'"$scratch"'/role.md" "Do the plan phase."
    ' 2>/dev/null)"
  local expected_path="$scratch/.flowai/launch/plan_prompt.md"
  if [[ ! -f "$expected_path" ]]; then
    printf 'FAIL %s: prompt file not created at %s\n' "$id" "$expected_path" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    rm -rf "$scratch"
    return
  fi
  local content
  content="$(cat "$expected_path")"
  local ok=true
  if [[ "$content" != *"You are a test role."* ]]; then
    printf 'FAIL %s: prompt file missing role content\n' "$id" >&2
    ok=false
  fi
  if [[ "$content" != *"Do the plan phase."* ]]; then
    printf 'FAIL %s: prompt file missing directive\n' "$id" >&2
    ok=false
  fi
  if [[ "$content" != *"ARTIFACT BOUNDARY"* ]]; then
    printf 'FAIL %s: prompt file missing artifact boundary\n' "$id" >&2
    ok=false
  fi
  if $ok; then
    flowai_test_pass "$id" "write_prompt creates file with role+directive+boundary"
  else
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── PHE-005: write_prompt creates launch/ directory if missing ───────────────
flowai_test_s_phe_005() {
  local id="PHE-005"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  printf '{}' > "$scratch/.flowai/config.json"
  # Deliberately do NOT create launch/
  printf '# role\n' > "$scratch/role.md"
  local _fh="$FLOWAI_HOME"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$_fh" \
    bash -c '
      source "$FLOWAI_HOME/src/core/phase.sh"
      flowai_phase_write_prompt "tasks" "'"$scratch"'/role.md" "Do tasks."
    ' 2>/dev/null
  if [[ -d "$scratch/.flowai/launch" ]] && [[ -f "$scratch/.flowai/launch/tasks_prompt.md" ]]; then
    flowai_test_pass "$id" "write_prompt creates launch/ directory if missing"
  else
    printf 'FAIL %s: launch/ dir or prompt file not created\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── PHE-006: resolve_role_prompt returns bundled fallback (no overrides) ─────
flowai_test_s_phe_006() {
  local id="PHE-006"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  printf '{}' > "$scratch/.flowai/config.json"
  local _fh="$FLOWAI_HOME"
  local result
  result="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$_fh" \
    bash -c '
      source "$FLOWAI_HOME/src/core/phase.sh"
      flowai_phase_resolve_role_prompt "plan"
    ' 2>/dev/null)"
  local expected="$FLOWAI_HOME/src/roles/backend-engineer.md"
  if [[ "$result" == "$expected" ]]; then
    flowai_test_pass "$id" "resolve_role_prompt returns bundled fallback when no overrides"
  else
    printf 'FAIL %s: expected %s, got %s\n' "$id" "$expected" "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── PHE-007: resolve_role_prompt tier 1 (phase-level override) wins ──────────
flowai_test_s_phe_007() {
  local id="PHE-007"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/roles"
  printf '{}' > "$scratch/.flowai/config.json"
  # Create tier 1 override: .flowai/roles/plan.md
  printf '# Phase-level override for plan\n' > "$scratch/.flowai/roles/plan.md"
  local _fh="$FLOWAI_HOME"
  local result
  result="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$_fh" \
    bash -c '
      source "$FLOWAI_HOME/src/core/phase.sh"
      flowai_phase_resolve_role_prompt "plan"
    ' 2>/dev/null)"
  local expected="$scratch/.flowai/roles/plan.md"
  if [[ "$result" == "$expected" ]]; then
    flowai_test_pass "$id" "resolve_role_prompt tier 1 (phase-level override) wins"
  else
    printf 'FAIL %s: expected %s, got %s\n' "$id" "$expected" "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── PHE-008: resolve_role_prompt tier 2 (role-name override) wins ────────────
flowai_test_s_phe_008() {
  local id="PHE-008"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/roles"
  printf '{}' > "$scratch/.flowai/config.json"
  # No tier 1 (no plan.md), but create tier 2: .flowai/roles/backend-engineer.md
  printf '# Role-name override for backend-engineer\n' > "$scratch/.flowai/roles/backend-engineer.md"
  local _fh="$FLOWAI_HOME"
  local result
  result="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$_fh" \
    bash -c '
      source "$FLOWAI_HOME/src/core/phase.sh"
      flowai_phase_resolve_role_prompt "plan"
    ' 2>/dev/null)"
  local expected="$scratch/.flowai/roles/backend-engineer.md"
  if [[ "$result" == "$expected" ]]; then
    flowai_test_pass "$id" "resolve_role_prompt tier 2 (role-name override) wins when no phase file"
  else
    printf 'FAIL %s: expected %s, got %s\n' "$id" "$expected" "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── PHE-009: session_prompt_end returns 0 when FLOWAI_TESTING=1 ──────────────
flowai_test_s_phe_009() {
  local id="PHE-009"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  printf '{}' > "$scratch/.flowai/config.json"
  local _fh="$FLOWAI_HOME"
  local rc=0
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$_fh" FLOWAI_TESTING=1 \
    bash -c '
      source "$FLOWAI_HOME/src/core/phase.sh"
      flowai_session_prompt_end
    ' 2>/dev/null || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "session_prompt_end returns 0 immediately when FLOWAI_TESTING=1"
  else
    printf 'FAIL %s: expected rc=0, got %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── PHE-010: phase_focus is a no-op when tmux is not available ───────────────
flowai_test_s_phe_010() {
  local id="PHE-010"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  printf '{}' > "$scratch/.flowai/config.json"
  local _fh="$FLOWAI_HOME"
  local clean_path
  clean_path="$(flowai_test_path_excluding_cmd tmux)"
  local rc=0
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$_fh" PATH="$clean_path" TMUX="" \
    bash -c '
      source "$FLOWAI_HOME/src/core/phase.sh"
      flowai_phase_focus "plan"
    ' 2>/dev/null || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "phase_focus is a no-op when tmux is not available (returns 0)"
  else
    printf 'FAIL %s: expected rc=0 without tmux, got %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}
