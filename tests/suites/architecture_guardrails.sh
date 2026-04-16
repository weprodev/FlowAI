#!/usr/bin/env bash
# FlowAI test suite — architecture guardrails
# These tests enforce structural invariants that prevent architectural drift.
# They run on every CI pass and catch violations BEFORE code review.
# shellcheck shell=bash

# shellcheck source=../../src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"

# ─── ARCH-001: No tool-specific logic in generic code ──────────────────────
# Core, phases, commands, bootstrap, and graph must NEVER branch on tool names.
# Tool-specific behavior belongs in src/tools/*.sh plugins only.
#
# Allowed exceptions (comments, config reads, plugin dispatch):
#   - Comments/docs (lines starting with #)
#   - Config reads: flowai_cfg_read / jq / default_id / .tools[$t]
#   - Plugin dispatch: flowai_tool_${tool}_ / declare -F "flowai_tool_
#   - Bootstrap scaffolding: editor-scaffold.sh (explicitly per-tool by design)
#   - Test banner labels
flowai_test_s_arch_001() {
  local id="ARCH-001"
  local violations=0
  local violation_details=""

  # Directories that must be tool-agnostic
  local -a scan_dirs=(
    "$FLOWAI_HOME/src/core"
    "$FLOWAI_HOME/src/phases"
    "$FLOWAI_HOME/src/commands"
    "$FLOWAI_HOME/src/graph"
  )

  # Tool names to check for
  local -a tool_names=("claude" "gemini" "cursor" "copilot")

  for dir in "${scan_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r -d '' file; do
      local relpath="${file#"$FLOWAI_HOME"/}"

      # Skip editor-scaffold.sh (explicitly per-tool by design)
      [[ "$relpath" == *"editor-scaffold.sh" ]] && continue

      for tool in "${tool_names[@]}"; do
        # Find lines containing the tool name (case-sensitive match)
        while IFS= read -r match_line; do
          [[ -z "$match_line" ]] && continue
          local lineno content
          lineno="$(echo "$match_line" | cut -d: -f1)"
          content="$(echo "$match_line" | cut -d: -f2-)"

          # Skip allowed patterns:
          # 1. Comments (# ...)
          if echo "$content" | grep -qE '^\s*#'; then
            continue
          fi
          # 2. Plugin dispatch: flowai_tool_${tool}_ or declare -F "flowai_tool_
          if echo "$content" | grep -qE 'flowai_tool_\$\{?tool|declare -F.*flowai_tool_'; then
            continue
          fi
          # 3. Config reads via jq or flowai_cfg
          if echo "$content" | grep -qE 'jq |flowai_cfg_|default_id|\.tools\['; then
            continue
          fi
          # 4. Log/event messages (string literals in log_* or printf for display)
          if echo "$content" | grep -qE 'log_(info|warn|error|success)|flowai_test_pass|_test_banner'; then
            continue
          fi
          # 5. Source/shellcheck directives
          if echo "$content" | grep -qE '^\s*source |shellcheck'; then
            continue
          fi
          # 6. Variable interpolation in generic patterns (e.g., ${tool}.sh)
          if echo "$content" | grep -qE '\$\{?tool'; then
            continue
          fi
          # 7. File glob patterns (src/tools/*.sh iteration)
          if echo "$content" | grep -qE 'tools/\*\.sh|_tool_plugin'; then
            continue
          fi
          # 8. Config defaults and fallback values (string assignments, arrays)
          if echo "$content" | grep -qE '^\s*(local )?_?[a-z_]+="[^"]*"|tool_names=\(|:-[a-z]'; then
            continue
          fi
          # 9. User-facing validation/error messages (config-validate, warn strings)
          if echo "$content" | grep -qE 'msg\+="|Field |is only for|from flowai models'; then
            continue
          fi
          # 10. Config-validate model checks (flowai_config_check_model_pair calls)
          if echo "$content" | grep -qE 'flowai_config_check_model_pair'; then
            continue
          fi
          # 11. Editor scaffold dispatch (wizard_tool fallback)
          if echo "$content" | grep -qE '_scaffold_tool='; then
            continue
          fi

          # This is a violation
          violations=$((violations + 1))
          violation_details="${violation_details}  ${relpath}:${lineno}: ${content}\n"
        done < <(grep -n -w "$tool" "$file" 2>/dev/null || true)
      done
    done < <(find "$dir" -name '*.sh' -print0 2>/dev/null)
  done

  if [[ "$violations" -eq 0 ]]; then
    flowai_test_pass "$id" "No tool-specific logic in generic code (core/phases/commands/graph)"
  else
    printf 'FAIL %s: %d tool-specific reference(s) in generic code:\n' "$id" "$violations" >&2
    printf '%b' "$violation_details" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── ARCH-002: All tool plugins implement required API ─────────────────────
# Every src/tools/<name>.sh must define the mandatory plugin functions.
flowai_test_s_arch_002() {
  local id="ARCH-002"
  local violations=0
  local violation_details=""
  local -a required_fns=("_run" "_print_models" "_run_oneshot")

  for plugin in "$FLOWAI_HOME/src/tools/"*.sh; do
    [[ -f "$plugin" ]] || continue
    local name
    name="$(basename "$plugin" .sh)"

    for fn_suffix in "${required_fns[@]}"; do
      local fn_name="flowai_tool_${name}${fn_suffix}"
      if ! grep -q "${fn_name}()" "$plugin" 2>/dev/null; then
        violations=$((violations + 1))
        violation_details="${violation_details}  ${name}.sh: missing ${fn_name}()\n"
      fi
    done
  done

  if [[ "$violations" -eq 0 ]]; then
    flowai_test_pass "$id" "All tool plugins implement required API (_run, _print_models, _run_oneshot)"
  else
    printf 'FAIL %s: %d missing plugin API function(s):\n' "$id" "$violations" >&2
    printf '%b' "$violation_details" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── ARCH-003: No cross-plugin dependencies ────────────────────────────────
# Tool plugins must not reference other plugin functions or internal helpers.
flowai_test_s_arch_003() {
  local id="ARCH-003"
  local violations=0
  local violation_details=""

  local -a tool_names=()
  for plugin in "$FLOWAI_HOME/src/tools/"*.sh; do
    [[ -f "$plugin" ]] || continue
    tool_names+=("$(basename "$plugin" .sh)")
  done

  for plugin in "$FLOWAI_HOME/src/tools/"*.sh; do
    [[ -f "$plugin" ]] || continue
    local this_tool
    this_tool="$(basename "$plugin" .sh)"

    for other_tool in "${tool_names[@]}"; do
      [[ "$other_tool" == "$this_tool" ]] && continue
      # Check for references to other plugin's functions (not in comments)
      while IFS= read -r match_line; do
        [[ -z "$match_line" ]] && continue
        local content
        content="$(echo "$match_line" | cut -d: -f2-)"
        echo "$content" | grep -qE '^\s*#' && continue
        violations=$((violations + 1))
        violation_details="${violation_details}  ${this_tool}.sh references ${other_tool}: ${content}\n"
      done < <(grep -n "flowai_tool_${other_tool}_\|_flowai_${other_tool}_" "$plugin" 2>/dev/null || true)
    done
  done

  if [[ "$violations" -eq 0 ]]; then
    flowai_test_pass "$id" "No cross-plugin dependencies between tool plugins"
  else
    printf 'FAIL %s: %d cross-plugin reference(s):\n' "$id" "$violations" >&2
    printf '%b' "$violation_details" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── ARCH-004: Polling loops have timeout guards ──────────────────────────
# Any phase with a "while true" polling loop must have a timeout to prevent
# indefinite hangs when the upstream agent crashes.
flowai_test_s_arch_004() {
  local id="ARCH-004"
  local violations=0
  local violation_details=""

  for phase_file in "$FLOWAI_HOME/src/phases/"*.sh; do
    [[ -f "$phase_file" ]] || continue
    local name
    name="$(basename "$phase_file")"
    # Skip master.sh — its main loop is intentionally infinite (orchestrator)
    [[ "$name" == "master.sh" ]] && continue

    if grep -q 'while true' "$phase_file" 2>/dev/null; then
      if ! grep -q 'FLOWAI_PHASE_TIMEOUT_SEC\|_poll_timeout\|timeout' "$phase_file" 2>/dev/null; then
        violations=$((violations + 1))
        violation_details="${violation_details}  ${name}: has 'while true' loop without timeout guard\n"
      fi
    fi
  done

  if [[ "$violations" -eq 0 ]]; then
    flowai_test_pass "$id" "All phase polling loops have timeout guards"
  else
    printf 'FAIL %s: %d polling loop(s) without timeout:\n' "$id" "$violations" >&2
    printf '%b' "$violation_details" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}
