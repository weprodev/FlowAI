#!/usr/bin/env bash
# FlowAI Gemini Tool Plugin
# shellcheck source=src/core/debug_session.sh
source "$FLOWAI_HOME/src/core/debug_session.sh"
# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"

# One-time user-visible hint: Google Gemini CLI often blocks 1–3 min on first auth per session.
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

flowai_tool_gemini_print_models() {
  # _flowai_print_tool_block is dynamically provided by the caller (models.sh)
  _flowai_print_tool_block "gemini"
}

# Gemini CLI (headless + some interactive runs) logs internal [LocalAgentExecutor]
# lines to stderr (subagent recursion skips). That noise is not useful in tmux
# panes and can interleave with stdout in confusing ways. Real stderr errors are
# preserved (they do not match this prefix).
_flowai_gemini_filter_executor_noise() {
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      \[LocalAgentExecutor\]*) continue ;;
    esac
    printf '%s\n' "$line"
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
  if [[ "$auto_approve" == "true" ]]; then
    cmd+=(-y)
  fi

  if [[ "$run_interactive" == "true" ]]; then
    local tmp_sys
    tmp_sys="$(mktemp "${FLOWAI_DIR:-$PWD/.flowai}/gemini_sys_XXXXXX")"
    trap 'rm -f "$tmp_sys"' EXIT
    echo "$sys_prompt" > "$tmp_sys"
    _flowai_gemini_slow_auth_hint_once
    # region agent log
    local _g0 _g1 _gw _sz
    _sz="$(wc -c < "$tmp_sys" | tr -d ' ')"
    _g0="$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)"
    GEMINI_SYSTEM_MD="$tmp_sys" "${cmd[@]}" 2> >(_flowai_gemini_filter_executor_noise >&2)
    local ext_code=$?
    _g1="$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)"
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
  echo "$sys_prompt" > "$tmp_sys"
  _flowai_gemini_slow_auth_hint_once
  # region agent log
  local _g0 _g1 _gw _sz _rc=0
  _sz="$(wc -c < "$tmp_sys" | tr -d ' ')"
  _g0="$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)"
  GEMINI_SYSTEM_MD="$tmp_sys" "${cmd[@]}" \
    "Execute the pipeline directive in your system prompt. Begin immediately." \
    < /dev/null 2> >(_flowai_gemini_filter_executor_noise >&2) || _rc=$?
  _g1="$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)"
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

  # Stderr: filter LocalAgentExecutor noise; stdout stays raw for callers (e.g. graph JSON).
  # region agent log
  local _g0 _g1 _gw _plen _rc=0
  _plen="${#prompt}"
  _flowai_gemini_slow_auth_hint_once
  _g0="$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)"
  gemini -m "$model" "$prompt" < /dev/null 2> >(_flowai_gemini_filter_executor_noise >&2) || _rc=$?
  if [[ -n "$_hb_pid" ]]; then
    kill "$_hb_pid" 2>/dev/null || true
    wait "$_hb_pid" 2>/dev/null || true
  fi
  # Match historical behavior: on failure emit '{}' on stdout and exit 0 (graph + callers rely on this).
  if [[ "$_rc" -ne 0 ]]; then
    echo '{}'
  fi
  _g1="$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)"
  _gw=$((_g1 - _g0))
  flowai_debug_session_log "H-B" "gemini.sh:flowai_tool_gemini_run_oneshot" "oneshot_master_review_finished" \
    "{\"model\":\"${model}\",\"gemini_wall_ms\":${_gw},\"prompt_chars\":${_plen},\"exit\":${_rc}}"
  # endregion
}
