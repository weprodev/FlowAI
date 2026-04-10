#!/usr/bin/env bash
# FlowAI test suite — tool plugin API compliance
# Tests that all tool plugins define the required functions.
# shellcheck shell=bash

source "$FLOWAI_HOME/src/core/log.sh"

# ─── TPL-001: All plugins define _run and _print_models ─────────────────────
flowai_test_s_tpl_001() {
  local id="TPL-001"
  local all_ok=true
  for tool in claude gemini cursor copilot; do
    local plugin="$FLOWAI_HOME/src/tools/${tool}.sh"
    if [[ ! -f "$plugin" ]]; then
      printf 'FAIL %s: plugin file missing: %s\n' "$id" "$plugin" >&2
      FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
      all_ok=false
      continue
    fi
    # Source in subshell to avoid polluting environment
    (
      source "$FLOWAI_HOME/src/core/log.sh"
      source "$FLOWAI_HOME/src/core/config.sh"
      source "$plugin"
      declare -F "flowai_tool_${tool}_run" >/dev/null 2>&1 || { echo "MISSING:run"; exit 1; }
      declare -F "flowai_tool_${tool}_print_models" >/dev/null 2>&1 || { echo "MISSING:print_models"; exit 1; }
    )
    if [[ $? -ne 0 ]]; then
      printf 'FAIL %s: plugin %s missing required functions\n' "$id" "$tool" >&2
      FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
      all_ok=false
    fi
  done
  [[ "$all_ok" == "true" ]] && flowai_test_pass "$id" "All plugins define _run and _print_models"
}

# ─── TPL-002: All plugins define _run_oneshot ────────────────────────────────
flowai_test_s_tpl_002() {
  local id="TPL-002"
  local all_ok=true
  for tool in claude gemini cursor copilot; do
    local plugin="$FLOWAI_HOME/src/tools/${tool}.sh"
    (
      source "$FLOWAI_HOME/src/core/log.sh"
      source "$FLOWAI_HOME/src/core/config.sh"
      source "$plugin"
      declare -F "flowai_tool_${tool}_run_oneshot" >/dev/null 2>&1 || exit 1
    )
    if [[ $? -ne 0 ]]; then
      printf 'FAIL %s: plugin %s missing _run_oneshot\n' "$id" "$tool" >&2
      FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
      all_ok=false
    fi
  done
  [[ "$all_ok" == "true" ]] && flowai_test_pass "$id" "All plugins define _run_oneshot"
}

# ─── TPL-003: Cursor/Copilot oneshot returns valid JSON fallback ─────────────
flowai_test_s_tpl_003() {
  local id="TPL-003"
  local all_ok=true
  for tool in cursor copilot; do
    local output
    output="$(
      source "$FLOWAI_HOME/src/core/log.sh"
      source "$FLOWAI_HOME/src/core/config.sh"
      source "$FLOWAI_HOME/src/tools/${tool}.sh"
      flowai_tool_${tool}_run_oneshot "model" "/dev/null" 2>/dev/null
    )"
    if ! printf '%s' "$output" | jq -e '.nodes != null and .edges != null' >/dev/null 2>&1; then
      printf 'FAIL %s: %s oneshot did not return valid JSON: %s\n' "$id" "$tool" "$output" >&2
      FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
      all_ok=false
    fi
  done
  [[ "$all_ok" == "true" ]] && flowai_test_pass "$id" "Cursor/Copilot oneshot returns valid JSON fallback"
}

# ─── TPL-004: Claude plugin uses --system-prompt in non-interactive mode ─────
flowai_test_s_tpl_004() {
  local id="TPL-004"
  local plugin="$FLOWAI_HOME/src/tools/claude.sh"
  if grep -q '\-\-system-prompt' "$plugin" 2>/dev/null; then
    flowai_test_pass "$id" "Claude plugin uses --system-prompt flag"
  else
    printf 'FAIL %s: Claude plugin does not use --system-prompt\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── TPL-005: Gemini plugin does not auto-approve in non-interactive mode ────
flowai_test_s_tpl_005() {
  local id="TPL-005"
  local plugin="$FLOWAI_HOME/src/tools/gemini.sh"
  # The bug was: auto_approve == "true" || run_interactive == "false"
  # The fix should be: auto_approve == "true" only
  if grep -q 'run_interactive.*==.*"false".*-y\|run_interactive.*-y' "$plugin" 2>/dev/null; then
    printf 'FAIL %s: Gemini plugin still auto-approves in non-interactive mode\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  else
    flowai_test_pass "$id" "Gemini plugin respects auto_approve setting"
  fi
}
