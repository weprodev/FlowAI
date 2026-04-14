#!/usr/bin/env bash
# FlowAI test suite — AI tool/model resolution
# Tests for flowai_ai_resolve_model_for_tool, flowai_ai_resolve_tool_and_model_for_phase,
# and flowai_ai_tool_is_paste_only in src/core/ai.sh.
# shellcheck shell=bash
#
# Isolated temp projects use: env FLOWAI_DIR=… FLOWAI_HOME=… bash -s <<'EOS' … EOS
# so ShellCheck does not treat exports as lost subshell assignments (SC2030/SC2031).

source "$FLOWAI_HOME/src/core/log.sh"

# ─── AIR-001: resolve_model empty raw returns catalog default ───────────────
flowai_test_s_air_001() {
  local id="AIR-001"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  cat > "$scratch/.flowai/config.json" <<'JSON'
{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}
JSON
  local result
  result="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/ai.sh"
flowai_ai_resolve_model_for_tool "gemini" ""
EOS
)"
  if [[ -n "$result" && "$result" != "null" ]]; then
    flowai_test_pass "$id" "resolve_model empty raw returns catalog default ($result)"
  else
    printf 'FAIL %s: expected non-empty catalog default, got: "%s"\n' "$id" "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── AIR-002: resolve_model passes valid model through ──────────────────────
flowai_test_s_air_002() {
  local id="AIR-002"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  cat > "$scratch/.flowai/config.json" <<'JSON'
{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}
JSON
  local result
  result="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/ai.sh"
flowai_ai_resolve_model_for_tool "gemini" "gemini-2.5-pro"
EOS
)"
  if [[ "$result" == "gemini-2.5-pro" ]]; then
    flowai_test_pass "$id" "resolve_model passes valid model through unchanged"
  else
    printf 'FAIL %s: expected "gemini-2.5-pro", got: "%s"\n' "$id" "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── AIR-003: resolve_model rejects GPT model for Claude ───────────────────
flowai_test_s_air_003() {
  local id="AIR-003"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  cat > "$scratch/.flowai/config.json" <<'JSON'
{"master":{"tool":"claude","model":"sonnet"}}
JSON
  local result
  result="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/ai.sh" 2>/dev/null
flowai_ai_resolve_model_for_tool "claude" "gpt-4o" 2>/dev/null
EOS
)"
  if [[ "$result" != "gpt-4o" && -n "$result" ]]; then
    flowai_test_pass "$id" "resolve_model rejects GPT model for Claude — returned '$result'"
  else
    printf 'FAIL %s: expected claude default (not gpt-4o), got: "%s"\n' "$id" "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── AIR-004: resolve_model unknown model falls back to default ─────────────
flowai_test_s_air_004() {
  local id="AIR-004"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  cat > "$scratch/.flowai/config.json" <<'JSON'
{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}
JSON
  local result
  result="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/ai.sh" 2>/dev/null
flowai_ai_resolve_model_for_tool "gemini" "nonexistent-model-xyz" 2>/dev/null
EOS
)"
  if [[ "$result" != "nonexistent-model-xyz" && -n "$result" ]]; then
    flowai_test_pass "$id" "resolve_model unknown model falls back to default ($result)"
  else
    printf 'FAIL %s: expected catalog default (not "nonexistent-model-xyz"), got: "%s"\n' "$id" "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── AIR-005: resolve_tool_and_model for master phase ───────────────────────
flowai_test_s_air_005() {
  local id="AIR-005"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  cat > "$scratch/.flowai/config.json" <<'JSON'
{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}
JSON
  local result
  result="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/ai.sh" 2>/dev/null
flowai_ai_resolve_tool_and_model_for_phase "master" 2>/dev/null
EOS
)"
  if [[ "$result" == "gemini:gemini-2.5-pro" ]]; then
    flowai_test_pass "$id" "resolve_tool_and_model for master returns gemini:gemini-2.5-pro"
  else
    printf 'FAIL %s: expected "gemini:gemini-2.5-pro", got: "%s"\n' "$id" "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── AIR-006: resolve_tool_and_model for pipeline phase ─────────────────────
flowai_test_s_air_006() {
  local id="AIR-006"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  cat > "$scratch/.flowai/config.json" <<'JSON'
{"master":{"tool":"gemini","model":"gemini-2.5-pro"},"pipeline":{"impl":"backend-engineer"},"roles":{"backend-engineer":{"tool":"claude","model":"sonnet"}}}
JSON
  local result
  result="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/ai.sh" 2>/dev/null
flowai_ai_resolve_tool_and_model_for_phase "impl" 2>/dev/null
EOS
)"
  if [[ "$result" == "claude:"* ]]; then
    flowai_test_pass "$id" "resolve_tool_and_model for pipeline phase returns claude tool ($result)"
  else
    printf 'FAIL %s: expected "claude:...", got: "%s"\n' "$id" "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── AIR-007: resolve_tool_and_model falls back to master tool ──────────────
flowai_test_s_air_007() {
  local id="AIR-007"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  # Role "team-lead" has no tool field — should fall back to master.tool=gemini
  cat > "$scratch/.flowai/config.json" <<'JSON'
{"master":{"tool":"gemini","model":"gemini-2.5-pro"},"pipeline":{"plan":"team-lead"},"roles":{"team-lead":{"model":"gemini-2.5-flash"}}}
JSON
  local result
  result="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/ai.sh" 2>/dev/null
flowai_ai_resolve_tool_and_model_for_phase "plan" 2>/dev/null
EOS
)"
  if [[ "$result" == "gemini:"* ]]; then
    flowai_test_pass "$id" "resolve_tool_and_model falls back to master tool ($result)"
  else
    printf 'FAIL %s: expected "gemini:...", got: "%s"\n' "$id" "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── AIR-008: tool_is_paste_only for unknown tool returns 1 ─────────────────
flowai_test_s_air_008() {
  local id="AIR-008"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  cat > "$scratch/.flowai/config.json" <<'JSON'
{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}
JSON
  local rc=0
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" \
    bash -c 'source "$FLOWAI_HOME/src/core/ai.sh" 2>/dev/null; flowai_ai_tool_is_paste_only "nonexistent_tool"' \
    || rc=$?
  if [[ "$rc" -eq 1 ]]; then
    flowai_test_pass "$id" "tool_is_paste_only for unknown tool returns 1"
  else
    printf 'FAIL %s: expected exit code 1, got: %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── AIR-009: tool_is_paste_only detects paste-only tools ───────────────────
flowai_test_s_air_009() {
  local id="AIR-009"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  cat > "$scratch/.flowai/config.json" <<'JSON'
{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}
JSON
  # cursor-agent is not on PATH in test env, so cursor reports paste-only (returns 0)
  local _empty_home
  _empty_home="$(mktemp -d)"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" PATH="/usr/bin:/bin" HOME="$_empty_home" \
    bash -c 'source "$FLOWAI_HOME/src/core/ai.sh" 2>/dev/null; flowai_ai_tool_is_paste_only "cursor"'
  local rc=$?
  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "tool_is_paste_only detects cursor as paste-only (no cursor-agent CLI)"
  else
    printf 'FAIL %s: expected exit code 0 (paste-only), got: %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$_empty_home"
  rm -rf "$scratch"
}

# ─── AIR-010: resolve_model allows unknown model with FLOWAI_ALLOW_UNKNOWN_MODEL=1
flowai_test_s_air_010() {
  local id="AIR-010"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  cat > "$scratch/.flowai/config.json" <<'JSON'
{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}
JSON
  local result
  result="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" FLOWAI_ALLOW_UNKNOWN_MODEL=1 bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/ai.sh" 2>/dev/null
flowai_ai_resolve_model_for_tool "gemini" "custom-model-xyz" 2>/dev/null
EOS
)"
  if [[ "$result" == "custom-model-xyz" ]]; then
    flowai_test_pass "$id" "resolve_model allows unknown model with FLOWAI_ALLOW_UNKNOWN_MODEL=1"
  else
    printf 'FAIL %s: expected "custom-model-xyz", got: "%s"\n' "$id" "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}
