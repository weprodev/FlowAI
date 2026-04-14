#!/usr/bin/env bash
# FlowAI test suite — tool plugin API compliance
# Tests that all tool plugins define the required functions.
# shellcheck shell=bash

# shellcheck source=../../src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"

# ─── TPL-001: All plugins define _run and _print_models ─────────────────────
flowai_test_s_tpl_001() {
  local id="TPL-001"
  local all_ok=true
  for tool_name in claude gemini cursor copilot; do
    local plugin="$FLOWAI_HOME/src/tools/${tool_name}.sh"
    if [[ ! -f "$plugin" ]]; then
      printf 'FAIL %s: plugin file missing: %s\n' "$id" "$plugin" >&2
      FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
      all_ok=false
      continue
    fi
    # Source in subshell to avoid polluting environment
    if ! (
      # shellcheck source=../../src/core/log.sh
      source "$FLOWAI_HOME/src/core/log.sh"
      # shellcheck source=../../src/core/config.sh
      source "$FLOWAI_HOME/src/core/config.sh"
      # shellcheck disable=SC1090
      source "$plugin"
      declare -F "flowai_tool_${tool_name}_run" >/dev/null 2>&1 || { echo "MISSING:run"; exit 1; }
      declare -F "flowai_tool_${tool_name}_print_models" >/dev/null 2>&1 || { echo "MISSING:print_models"; exit 1; }
    ); then
      printf 'FAIL %s: plugin %s missing required functions\n' "$id" "$tool_name" >&2
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
  for tool_name in claude gemini cursor copilot; do
    local plugin="$FLOWAI_HOME/src/tools/${tool_name}.sh"
    if ! (
      # shellcheck source=../../src/core/log.sh
      source "$FLOWAI_HOME/src/core/log.sh"
      # shellcheck source=../../src/core/config.sh
      source "$FLOWAI_HOME/src/core/config.sh"
      # shellcheck disable=SC1090
      source "$plugin"
      declare -F "flowai_tool_${tool_name}_run_oneshot" >/dev/null 2>&1 || exit 1
    ); then
      printf 'FAIL %s: plugin %s missing _run_oneshot\n' "$id" "$tool_name" >&2
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
  local _empty_home _fh
  _empty_home="$(mktemp -d)"
  _fh="$FLOWAI_HOME"
  for tool_name in cursor copilot; do
    local output
    # Isolate PATH/HOME so a real cursor-agent on the developer machine does not run
    # (would return non-JSON). Copilot gets the same isolation for consistency.
    # Use FLOWAI_TPL_TOOL (not bash -s "$tool") so $1 is never relied on — some shells/CI
    # disagree on how bash -s maps argv to $1 for stdin scripts.
    output="$(PATH="/usr/bin:/bin" HOME="$_empty_home" FLOWAI_HOME="$_fh" FLOWAI_TPL_TOOL="$tool_name" bash -s <<'EOS'
# shellcheck source=../../src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"
# shellcheck source=../../src/core/config.sh
source "$FLOWAI_HOME/src/core/config.sh"
if [[ "$FLOWAI_TPL_TOOL" == "cursor" ]]; then
  # shellcheck source=../../src/tools/cursor.sh
  source "$FLOWAI_HOME/src/tools/cursor.sh"
  flowai_tool_cursor_run_oneshot "model" "/dev/null" 2>/dev/null
elif [[ "$FLOWAI_TPL_TOOL" == "copilot" ]]; then
  # shellcheck source=../../src/tools/copilot.sh
  source "$FLOWAI_HOME/src/tools/copilot.sh"
  flowai_tool_copilot_run_oneshot "model" "/dev/null" 2>/dev/null
fi
EOS
)"
    if ! printf '%s' "$output" | jq -e '.nodes != null and .edges != null' >/dev/null 2>&1; then
      printf 'FAIL %s: %s oneshot did not return valid JSON: %s\n' "$id" "$tool_name" "$output" >&2
      FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
      all_ok=false
    fi
  done
  rm -rf "$_empty_home"
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

# ─── TPL-006: Gemini interactive mode uses GEMINI_SYSTEM_MD ──────────────────
flowai_test_s_tpl_006() {
  local id="TPL-006"
  local plugin="$FLOWAI_HOME/src/tools/gemini.sh"
  if grep -q 'GEMINI_SYSTEM_MD=' "$plugin" 2>/dev/null; then
    flowai_test_pass "$id" "Gemini interactive uses GEMINI_SYSTEM_MD (not -p)"
  else
    printf 'FAIL %s: Gemini plugin does not use GEMINI_SYSTEM_MD for interactive mode\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── TPL-007: Gemini oneshot does not pass raw sys_prompt as positional arg ──
flowai_test_s_tpl_007() {
  local id="TPL-007"
  local plugin="$FLOWAI_HOME/src/tools/gemini.sh"
  # The old bug: "${cmd[@]}" "$sys_prompt" < /dev/null
  # The fix: uses GEMINI_SYSTEM_MD temp file for oneshot too
  if grep -Fq "\"\${cmd[@]}\" \"\$sys_prompt\"" "$plugin" 2>/dev/null; then
    printf 'FAIL %s: Gemini oneshot still passes raw sys_prompt as positional arg\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  else
    flowai_test_pass "$id" "Gemini oneshot uses GEMINI_SYSTEM_MD (no ARG_MAX risk)"
  fi
}

# ─── TPL-008: No mktemp template has a suffix after XXXXXX ───────────────────
# BSD mktemp (macOS) requires XXXXXX at the very end of the template string.
# A suffix like .md causes mktemp to treat the Xs literally → "File exists".
flowai_test_s_tpl_008() {
  local id="TPL-008"
  local bad_lines
  # Match mktemp calls where XXXXXX is followed by anything other than quote/paren/whitespace
  bad_lines="$(grep -rnE 'mktemp.*XXXXXX[^"'\'')\s]' "$FLOWAI_HOME/src" 2>/dev/null || true)"
  if [[ -n "$bad_lines" ]]; then
    printf 'FAIL %s: mktemp template has suffix after XXXXXX (breaks BSD mktemp):\n%s\n' \
      "$id" "$bad_lines" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  else
    flowai_test_pass "$id" "No mktemp template has a suffix after XXXXXX (BSD-safe)"
  fi
}

# ─── TPL-009: Cursor plugin has cursor-agent CLI integration ─────────────────
flowai_test_s_tpl_009() {
  local id="TPL-009"
  local plugin="$FLOWAI_HOME/src/tools/cursor.sh"
  local all_ok=true
  # Must contain cursor-agent CLI invocation
  if ! grep -q 'cursor-agent' "$plugin" 2>/dev/null; then
    printf 'FAIL %s: Cursor plugin does not reference cursor-agent CLI\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    all_ok=false
  fi
  # Must reference shared constraint reminder from ai.sh (DRY)
  if ! grep -q 'FLOWAI_CONSTRAINT_REMINDER' "$plugin" 2>/dev/null; then
    printf 'FAIL %s: Cursor plugin missing FLOWAI_CONSTRAINT_REMINDER reference\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    all_ok=false
  fi
  [[ "$all_ok" == "true" ]] && flowai_test_pass "$id" "Cursor plugin has cursor-agent CLI integration and constraint reminder"
}

# ─── TPL-010: Cursor plugin has paste-only fallback ──────────────────────────
flowai_test_s_tpl_010() {
  local id="TPL-010"
  local plugin="$FLOWAI_HOME/src/tools/cursor.sh"
  if grep -q '_flowai_cursor_paste_only_run\|paste-only\|paste.only' "$plugin" 2>/dev/null; then
    flowai_test_pass "$id" "Cursor plugin has paste-only fallback when CLI missing"
  else
    printf 'FAIL %s: Cursor plugin missing paste-only fallback path\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── TPL-011: ai.sh uses plugin probe for paste-only (tool-agnostic) ─────────
flowai_test_s_tpl_011() {
  local id="TPL-011"
  local ai_file="$FLOWAI_HOME/src/core/ai.sh"
  # cursor should NOT be unconditionally grouped with copilot in is_paste_only
  if grep -q 'cursor|copilot)' "$ai_file" 2>/dev/null; then
    printf 'FAIL %s: ai.sh still groups cursor with copilot as unconditionally paste-only\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  else
    # Verify ai.sh uses the tool-agnostic plugin probe pattern
    if grep -q 'flowai_tool_${tool}_is_paste_only' "$ai_file" 2>/dev/null; then
      flowai_test_pass "$id" "ai.sh uses plugin probe for paste-only (tool-agnostic)"
    else
      printf 'FAIL %s: ai.sh does not use plugin probe pattern for is_paste_only\n' "$id" >&2
      FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    fi
  fi
}

# ─── TPL-012: Cursor resolves CLI without PATH + avoids CURSOR_RULES_FILE ────
flowai_test_s_tpl_012() {
  local id="TPL-012"
  local plugin="$FLOWAI_HOME/src/tools/cursor.sh"
  local ok=true
  if ! grep -q '_flowai_cursor_resolve_executable' "$plugin" 2>/dev/null; then
    printf 'FAIL %s: cursor.sh missing _flowai_cursor_resolve_executable (tmux PATH fix)\n' "$id" >&2
    ok=false
  fi
  if grep -q 'CURSOR_RULES_FILE' "$plugin" 2>/dev/null; then
    printf 'FAIL %s: cursor.sh must not use CURSOR_RULES_FILE (unsupported by cursor-agent)\n' "$id" >&2
    ok=false
  fi
  if $ok; then
    flowai_test_pass "$id" "Cursor plugin resolves CLI without PATH and avoids CURSOR_RULES_FILE"
  else
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

