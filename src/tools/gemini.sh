#!/usr/bin/env bash
# FlowAI Gemini Tool Plugin
# shellcheck source=src/core/debug_session.sh
source "$FLOWAI_HOME/src/core/debug_session.sh"
# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"

# One-time user-visible hint: Google Gemini CLI often blocks 1–3 min on first auth per session.
# Inject FlowAI rules into GEMINI.md for Gemini CLI subagent propagation.
# Gemini CLI reads GEMINI.md from the project root for project-level instructions.
# Args: $1=content (tool-agnostic rules from flowai_ai_project_config_content)
flowai_tool_gemini_inject_project_config() {
  local content="$1"
  local marker_start="<!-- FLOWAI:START -->"
  local marker_end="<!-- FLOWAI:END -->"
  local gemini_md="$PWD/GEMINI.md"
  local block="${marker_start}
${content}
${marker_end}"

  if [[ -f "$gemini_md" ]]; then
    local cleaned
    cleaned="$(sed "/${marker_start}/,/${marker_end}/d" "$gemini_md")"
    printf '%s\n\n%s\n' "$cleaned" "$block" > "$gemini_md"
  else
    printf '%s\n' "$block" > "$gemini_md"
  fi
}

# Clean up Gemini-specific state files between sessions.
# Args: $1=FLOWAI_DIR path
flowai_tool_gemini_cleanup() {
  local flowai_dir="$1"
  rm -f "$flowai_dir/gemini_slow_auth_hint_shown" 2>/dev/null || true
}

_flowai_gemini_slow_auth_hint_once() {
  [[ "${FLOWAI_GEMINI_AUTH_HINT:-1}" == "0" ]] && return 0
  local hint="${FLOWAI_DIR:-$PWD/.flowai}/gemini_slow_auth_hint_shown"
  [[ -f "$hint" ]] && return 0
  log_info "Gemini CLI: first call each session often pauses 1–3 min on auth (you may see \"Loaded cached credentials\"); later calls are usually faster."
  touch "$hint" 2>/dev/null || true
}
# Defines the two required plugin API functions:
#   flowai_tool_gemini_print_models  — used by: flowai models list gemini
#   flowai_tool_gemini_run           — used by: ai.sh dispatcher
# shellcheck shell=bash

# Validate model ID for Gemini CLI. Falls back to catalog default if unknown.
# Args: $1=raw model ID
# Prints: validated model ID (or fallback)
flowai_tool_gemini_validate_model() {
  local raw="$1"
  [[ "${FLOWAI_ALLOW_UNKNOWN_MODEL:-0}" == "1" ]] && { printf '%s' "$raw"; return; }
  if declare -F flowai_models_catalog_contains >/dev/null 2>&1 && flowai_models_catalog_contains "gemini" "$raw"; then
    printf '%s' "$raw"
    return
  fi
  local fb
  fb="$(flowai_cfg_default_model_for_tool gemini)"
  if [[ "$fb" != "$raw" ]]; then
    log_warn "Model '$raw' is not in catalog for Gemini — using '$fb'. Run: flowai models list gemini"
  fi
  printf '%s' "$fb"
}

flowai_tool_gemini_print_models() {
  # _flowai_print_tool_block is dynamically provided by the caller (models.sh)
  _flowai_print_tool_block "gemini"
}

# Gemini CLI stderr filter — configurable via FLOWAI_AGENT_VERBOSE.
#
# [LocalAgentExecutor] lines are the agent's execution trace: tool calls, file
# reads, searches, code writes. They show what the agent is *thinking and doing*.
#
# FLOWAI_AGENT_VERBOSE=1 (default): pass through with a dimmed prefix so the user
#   sees the agent's step-by-step reasoning in real time.
# FLOWAI_AGENT_VERBOSE=0: strip [LocalAgentExecutor] lines (old silent behavior).
_flowai_gemini_filter_stderr() {
  local verbose="${FLOWAI_AGENT_VERBOSE:-1}"
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      \[LocalAgentExecutor\]*)
        if [[ "$verbose" == "1" ]]; then
          # Dim prefix so thinking lines are visually distinct from primary output
          printf '\033[2m%s\033[0m\n' "$line"
        fi
        # When verbose=0, skip the line (old behavior)
        ;;
      *)
        printf '%s\n' "$line"
        ;;
    esac
  done
}

# Execute a prompt against the Gemini CLI.
# Args: $1=model  $2=auto_approve  $3=run_interactive  $4=sys_prompt
flowai_tool_gemini_run() {
  local model="$1"
  local auto_approve="$2"
  local run_interactive="$3"
  local sys_prompt="$4"

  local cmd=(gemini -m "$model")
  # Non-interactive phases have no stdin for confirmations — same rule as Claude
  # (--permission-mode acceptEdits) and Cursor (--yolo): auto-approve tool use so
  # tasks.md / plan.md etc. are actually written when auto_approve is false in config.
  if [[ "$run_interactive" == "false" ]] || [[ "$auto_approve" == "true" ]]; then
    cmd+=(-y)
  fi

  if [[ "$run_interactive" == "true" ]]; then
    local tmp_sys
    tmp_sys="$(mktemp "${FLOWAI_DIR:-$PWD/.flowai}/gemini_sys_XXXXXX")"
    trap 'rm -f "$tmp_sys"' EXIT
    {
      printf '%s\n' "$sys_prompt"
      # FLOWAI_CONSTRAINT_REMINDER rule 4 (ai.sh): portable regex — Gemini CLI
      # grep_search uses a limited engine; PCRE (?i) etc. are not interchangeable with terminal grep -P.
      printf '\n%s\n' "${FLOWAI_CONSTRAINT_REMINDER:-}"
    } > "$tmp_sys"
    _flowai_gemini_slow_auth_hint_once
    # region agent log
    local _g0 _g1 _gw _sz
    _sz="$(wc -c < "$tmp_sys" | tr -d ' ')"
    _g0="$(date +%s)000"
    # Send initial prompt to anchor Gemini to the pipeline workflow (same pattern as Claude).
    GEMINI_SYSTEM_MD="$tmp_sys" "${cmd[@]}" \
      "Read your PIPELINE DIRECTIVE and HARD CONSTRAINTS in the system prompt. You are inside a FlowAI pipeline phase. Follow the STAGED WORKFLOW exactly as written — begin with step 1 now. Do NOT deviate from the directive." \
      2> >(_flowai_gemini_filter_stderr >&2)
    local ext_code=$?
    _g1="$(date +%s)000"
    _gw=$((_g1 - _g0))
    flowai_debug_session_log "H-B" "gemini.sh:flowai_tool_gemini_run" "interactive_gemini_finished" \
      "{\"model\":\"${model}\",\"interactive\":true,\"gemini_wall_ms\":${_gw},\"system_md_bytes\":${_sz},\"exit\":${ext_code}}"
    # endregion
    rm -f "$tmp_sys"
    trap - EXIT
    return $ext_code
  fi

  # Oneshot: write enriched prompt to temp file via GEMINI_SYSTEM_MD to avoid
  # ARG_MAX truncation on large prompts (graph + skills + event log context).
  local tmp_sys
  tmp_sys="$(mktemp "${FLOWAI_DIR:-$PWD/.flowai}/gemini_sys_XXXXXX")"
  trap 'rm -f "$tmp_sys"' EXIT
  {
    printf '%s\n' "$sys_prompt"
    # See interactive branch: CONSTRAINT_REMINDER rule 4 vs Gemini grep_search engine.
    printf '\n%s\n' "${FLOWAI_CONSTRAINT_REMINDER:-}"
  } > "$tmp_sys"
  _flowai_gemini_slow_auth_hint_once
  # region agent log
  local _g0 _g1 _gw _sz _rc=0 _ps
  _sz="$(wc -c < "$tmp_sys" | tr -d ' ')"
  _g0="$(date +%s)000"

  local _initial_prompt="Execute the PIPELINE DIRECTIVE in your system prompt. HARD CONSTRAINTS are MANDATORY — you may ONLY write to the OUTPUT FILE specified in the directive. Do NOT create any other files. If a knowledge graph is available, read GRAPH_REPORT.md BEFORE searching files. Begin immediately."

  # FLOWAI_AGENT_VERBOSE=1 (default): use --output-format stream-json so the tmux
  # pane shows real-time thinking (tool calls, file reads, reasoning) — same
  # pattern as the Cursor plugin's streaming mode.
  # FLOWAI_AGENT_VERBOSE=0: original quiet behavior (plain stdout, stderr filter only).
  if [[ "${FLOWAI_AGENT_VERBOSE:-1}" == "1" ]]; then
    { GEMINI_SYSTEM_MD="$tmp_sys" "${cmd[@]}" --output-format stream-json \
        "$_initial_prompt" \
        < /dev/null 2> >(_flowai_gemini_filter_stderr >&2) \
        | python3 "$FLOWAI_HOME/src/tools/gemini_formatter.py"; _ps=("${PIPESTATUS[@]}"); } || true
    _rc="${_ps[0]}"
  else
    GEMINI_SYSTEM_MD="$tmp_sys" "${cmd[@]}" \
      "$_initial_prompt" \
      < /dev/null 2> >(_flowai_gemini_filter_stderr >&2) || _rc=$?
  fi

  _g1="$(date +%s)000"
  _gw=$((_g1 - _g0))
  flowai_debug_session_log "H-B" "gemini.sh:flowai_tool_gemini_run" "oneshot_phase_gemini_finished" \
    "{\"model\":\"${model}\",\"interactive\":false,\"gemini_wall_ms\":${_gw},\"system_md_bytes\":${_sz},\"exit\":${_rc}}"
  # endregion
  if [[ "${_rc:-0}" -ne 0 ]]; then
    rm -f "$tmp_sys"
    trap - EXIT
    return "${_rc}"
  fi
  rm -f "$tmp_sys"
  trap - EXIT
}

# Non-interactive single-shot invocation for graph semantic extraction.
# Args: $1=model  $2=prompt_file
# Returns: raw LLM output on stdout.
#
# FLOWAI_GEMINI_ONESHOT_HEARTBEAT_SEC (default 8):
#   While the Gemini CLI runs, log a progress line to stderr every N seconds so
#   tmux panes do not look "stuck" with no output. Set to 0 to disable.
flowai_tool_gemini_run_oneshot() {
  local model="$1"
  local prompt_file="$2"
  local prompt
  prompt="$(cat "$prompt_file")"

  local _hb_pid="" _hb_sec="${FLOWAI_GEMINI_ONESHOT_HEARTBEAT_SEC:-8}"
  if [[ "$_hb_sec" =~ ^[0-9]+$ ]] && [[ "$_hb_sec" -gt 0 ]]; then
    (
      local elapsed=0
      while sleep "$_hb_sec"; do
        elapsed=$((elapsed + _hb_sec))
        log_info "⏳ Gemini oneshot still running… (${elapsed}s elapsed, output follows when the CLI finishes or streams)" >&2
      done
    ) &
    _hb_pid=$!
  fi

  # Headless oneshot: Gemini CLI defaults positional "query" to INTERACTIVE mode; use
  # -p/--prompt for non-interactive (see `gemini --help`). Without -p, stdin is /dev/null
  # but the session still targets interactive semantics — slow, stuck, or flaky.
  # -y matches flowai_tool_gemini_run non-interactive: no tty to approve tool actions.
  # Stderr: filter via _flowai_gemini_filter_stderr (configurable via FLOWAI_AGENT_VERBOSE);
  # stdout stays raw for callers (e.g. graph JSON).
  # region agent log
  local _g0 _g1 _gw _plen _rc=0
  _plen="${#prompt}"
  _flowai_gemini_slow_auth_hint_once
  _g0="$(date +%s)000"
  gemini -m "$model" -y -p "$prompt" < /dev/null 2> >(_flowai_gemini_filter_stderr >&2) || _rc=$?
  if [[ -n "$_hb_pid" ]]; then
    kill "$_hb_pid" 2>/dev/null || true
    wait "$_hb_pid" 2>/dev/null || true
  fi
  # Graph semantic pass: on failure emit '{}' on stdout (best-effort JSON). Exit code
  # still reflects CLI status so Master oneshot / callers can detect tool errors.
  if [[ "$_rc" -ne 0 ]]; then
    echo '{}'
  fi
  _g1="$(date +%s)000"
  _gw=$((_g1 - _g0))
  flowai_debug_session_log "H-B" "gemini.sh:flowai_tool_gemini_run_oneshot" "oneshot_master_review_finished" \
    "{\"model\":\"${model}\",\"gemini_wall_ms\":${_gw},\"prompt_chars\":${_plen},\"exit\":${_rc}}"
  # endregion
  return "${_rc}"
}
