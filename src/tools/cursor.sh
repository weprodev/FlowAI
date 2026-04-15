#!/usr/bin/env bash
# FlowAI Cursor Tool Plugin
# Defines the required plugin API functions:
#   flowai_tool_cursor_print_models  — used by: flowai models list cursor
#   flowai_tool_cursor_run           — used by: ai.sh dispatcher
#   flowai_tool_cursor_run_oneshot   — used by: ai.sh oneshot dispatcher
#   flowai_tool_cursor_inject_project_config — used by: ai.sh config injection
#
# When the Cursor Agent CLI is available, this plugin matches Claude/Gemini flow
# (interactive REPL, headless phases, oneshot). Session instructions are passed
# via a staged prompt file + path in the initial message (no --system-prompt).
# When the CLI is not found, falls back to paste-only with a clear install hint.
#
# shellcheck shell=bash

# Inject FlowAI rules into .cursorrules for Cursor AI subagent propagation.
# Cursor reads .cursorrules from the project root for project-level instructions.
# Args: $1=content (tool-agnostic rules from flowai_ai_project_config_content)
flowai_tool_cursor_inject_project_config() {
  local content="$1"
  local marker_start="<!-- FLOWAI:START -->"
  local marker_end="<!-- FLOWAI:END -->"
  local cursor_rules="$PWD/.cursorrules"
  local block="${marker_start}
${content}
${marker_end}"

  if [[ -f "$cursor_rules" ]]; then
    local cleaned
    cleaned="$(sed "/${marker_start}/,/${marker_end}/d" "$cursor_rules")"
    printf '%s\n\n%s\n' "$cleaned" "$block" > "$cursor_rules"
  else
    printf '%s\n' "$block" > "$cursor_rules"
  fi
}

flowai_tool_cursor_print_models() {
  # _flowai_print_tool_block is dynamically provided by the caller (models.sh)
  _flowai_print_tool_block "cursor"
}

# ─── CLI Detection ───────────────────────────────────────────────────────────

# Resolve absolute path to the Cursor Agent binary.
# Official install symlinks both `cursor-agent` and `agent` under ~/.local/bin.
# tmux and non-login shells often omit ~/.local/bin from PATH, so we probe
# common locations after PATH — otherwise FlowAI wrongly falls back to paste-only.
_flowai_cursor_resolve_executable() {
  local p
  p="$(command -v cursor-agent 2>/dev/null)" && [[ -n "$p" ]] && { printf '%s' "$p"; return 0; }
  p="$(command -v agent 2>/dev/null)" && [[ -n "$p" ]] && { printf '%s' "$p"; return 0; }
  for p in "${HOME}/.local/bin/cursor-agent" "${HOME}/.local/bin/agent"; do
    [[ -x "$p" ]] && { printf '%s' "$p"; return 0; }
  done
  return 1
}

# Returns 0 if Cursor Agent CLI is runnable.
_flowai_cursor_cli_available() {
  _flowai_cursor_resolve_executable >/dev/null
}

# Plugin API: tell the dispatcher whether Cursor is currently paste-only.
# When cursor-agent is installed → not paste-only (full CLI mode).
# When missing → paste-only (user must paste prompts into the IDE).
flowai_tool_cursor_is_paste_only() {
  _flowai_cursor_cli_available && return 1 || return 0
}

# Plugin API: called by the init wizard after tool selection.
# If cursor-agent is missing, offers to install it interactively.
# Non-interactive (testing) environments skip the prompt.
flowai_tool_cursor_check_deps() {
  _flowai_cursor_cli_available && return 0

  log_warn "cursor-agent CLI is not installed."
  log_info "Without it, Cursor runs in paste-only mode (you manually paste prompts into the IDE)."
  log_info "With cursor-agent, FlowAI orchestrates Cursor directly from the terminal — same experience as Claude/Gemini."
  printf "\n"

  if [[ ! -t 0 ]] || [[ "${FLOWAI_TESTING:-0}" == "1" ]]; then
    log_info "Install cursor-agent:  curl https://cursor.com/install -fsSL | bash"
    return 0
  fi

  read -r -p "Install cursor-agent now? [Y/n]: " _ans_cursor
  if [[ ! "$_ans_cursor" =~ ^[nN] ]]; then
    log_info "Installing cursor-agent..."
    if curl https://cursor.com/install -fsSL | bash; then
      log_success "cursor-agent installed."
    else
      log_warn "cursor-agent install failed. You can install manually later:"
      printf '  curl https://cursor.com/install -fsSL | bash\n'
      log_info "FlowAI will fall back to paste-only mode until cursor-agent is available."
    fi
  else
    log_info "Skipped cursor-agent install. FlowAI will use paste-only mode for Cursor."
    log_info "Install later:  curl https://cursor.com/install -fsSL | bash"
  fi
  printf "\n"
}

# Cursor uses the shared FLOWAI_CONSTRAINT_REMINDER from ai.sh for sandwich
# reinforcement. Unlike Claude (which has its own --append-system-prompt constant),
# Cursor writes it directly into the session prompt file.

# ─── Usage-Limit Auto-Fallback ───────────────────────────────────────────────
# Cursor CLI exits non-zero with "out of usage" when the configured model's
# quota is exhausted. Instead of crashing the pipeline, detect the error and
# automatically retry with --model auto (the unlimited fallback tier).

# Check if a log file contains the Cursor "out of usage" / "Switch to auto" error.
# Args: $1=path to captured output file
# Returns: 0 if usage-limit error detected, 1 otherwise.
_flowai_cursor_is_usage_exhausted() {
  local logfile="$1"
  [[ -f "$logfile" ]] || return 1
  grep -qi 'out of usage\|switch to auto\|increase your limit' "$logfile" 2>/dev/null
}

# ─── Paste-Only Fallback ─────────────────────────────────────────────────────
# When cursor-agent is not installed, print the prompt for manual paste into Cursor.

_flowai_cursor_paste_only_run() {
  local sys_prompt="$1"
  log_warn "Cursor Agent CLI not found on PATH — paste-only mode."
  if [[ -x "${HOME}/.local/bin/cursor-agent" ]] || [[ -x "${HOME}/.local/bin/agent" ]]; then
    log_warn "Cursor Agent is installed under ~/.local/bin but not on PATH in this session (common in tmux)."
    log_info "Fix: export PATH=\"\$HOME/.local/bin:\$PATH\" then restart this session, or add ~/.local/bin to your shell profile."
  else
    log_info "Install for full automation:  curl https://cursor.com/install -fsSL | bash"
  fi
  log_warn "Paste the following prompt into Cursor Composer (Agent tab):"
  printf '\n%s\n' "$sys_prompt"
  printf '\n%s\n' "${FLOWAI_CONSTRAINT_REMINDER:-}"
  return 0
}

# ─── Main Run Function ──────────────────────────────────────────────────────

# Execute a prompt against the Cursor Agent CLI.
# Args: $1=model  $2=auto_approve  $3=run_interactive  $4=sys_prompt
# Reads: FLOWAI_DIR (for temp files), FLOWAI_CURRENT_PHASE (set by flowai_ai_run)
flowai_tool_cursor_run() {
  local model="$1"
  local auto_approve="$2"
  local run_interactive="$3"
  local sys_prompt="$4"

  local _ca
  _ca="$(_flowai_cursor_resolve_executable)" || {
    _flowai_cursor_paste_only_run "$sys_prompt"
    return 0
  }

  # cursor-agent has no --system-prompt. Load rules from project root only.
  # Pass the full orchestration prompt via a file under .flowai/ and reference
  # its absolute path in the initial message (Cursor reads paths via tools).
  local flowai_dir="${FLOWAI_DIR:-$PWD/.flowai}"
  mkdir -p "$flowai_dir" || {
    log_error "Cannot create $flowai_dir — cannot stage Cursor session prompt."
    return 1
  }

  local tmp_prompt
  tmp_prompt="$(mktemp "${flowai_dir}/cursor_session_prompt_XXXXXX")"
  trap 'rm -f "$tmp_prompt"' EXIT
  {
    printf '%s\n\n' "$sys_prompt"
    printf '%s\n' "${FLOWAI_CONSTRAINT_REMINDER:-}"
  } > "$tmp_prompt"

  local abs_prompt
  abs_prompt="$(cd "$(dirname "$tmp_prompt")" && pwd)/$(basename "$tmp_prompt")"

  local cmd=("$_ca")
  # Model selection
  if [[ -n "$model" && "$model" != "default" ]]; then
    cmd+=(--model "$model")
  fi

  # Non-interactive or auto-approve: --yolo lets cursor-agent apply edits without
  # per-change confirmation (no stdin in tmux phase panes).
  if [[ "$run_interactive" == "false" ]] || [[ "$auto_approve" == "true" ]]; then
    cmd+=(--yolo)
  fi

  local _initial_prompt="Your complete PIPELINE DIRECTIVE, HARD CONSTRAINTS, skills, and STAGED WORKFLOW are in this file — read it fully before acting: ${abs_prompt}

You are inside a FlowAI pipeline phase. Follow the STAGED WORKFLOW exactly as written — begin with step 1 now. Do NOT deviate from the directive."

  # region agent log
  local _c0 _c1 _cw _sz _rc=0
  _sz="$(wc -c < "$tmp_prompt" | tr -d ' ')"
  _c0="$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)"

  # Temp file to capture output for usage-limit detection
  local _cursor_log
  _cursor_log="$(mktemp "${flowai_dir}/cursor_run_log_XXXXXX")"

  if [[ "$run_interactive" == "true" ]]; then
    "${cmd[@]}" "$_initial_prompt" 2>&1 | tee "$_cursor_log" || _rc=$?

    # Auto-fallback: if the model's quota is exhausted, retry with --model auto
    if [[ "$_rc" -ne 0 ]] && _flowai_cursor_is_usage_exhausted "$_cursor_log"; then
      log_warn "⚡ Model '$model' usage exhausted — switching to Auto..."
      _rc=0
      local auto_cmd=("$_ca" --model auto)
      [[ "$auto_approve" == "true" ]] && auto_cmd+=(--yolo)
      "${auto_cmd[@]}" "$_initial_prompt" || _rc=$?
    fi
    rm -f "$_cursor_log"

    _c1="$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)"
    _cw=$((_c1 - _c0))
    flowai_debug_session_log "H-B" "cursor.sh:flowai_tool_cursor_run" "interactive_cursor_finished" \
      "{\"model\":\"${model}\",\"interactive\":true,\"cursor_wall_ms\":${_cw},\"prompt_bytes\":${_sz},\"exit\":${_rc}}"
    rm -f "$tmp_prompt"
    trap - EXIT
    return "$_rc"
  fi

  # Non-interactive: agent runs autonomously, then exits when work is done.
  # FLOWAI_AGENT_VERBOSE=1 (default): use --output-format stream-json so the tmux
  # pane shows real-time thinking (tool calls, file reads, reasoning).
  # FLOWAI_AGENT_VERBOSE=0: use -p (print mode) for buffered, quieter output.
  # --trust and explicit --workspace are only valid with --print; interactive Master
  # uses the REPL path without -p and must not pass --trust (CLI error otherwise).
  local _ps
  if [[ "${FLOWAI_AGENT_VERBOSE:-1}" == "1" ]]; then
    { "${cmd[@]}" --workspace "$PWD" --trust --output-format stream-json "$_initial_prompt" < /dev/null 2>&1 | tee "$_cursor_log" | python3 "$FLOWAI_HOME/src/tools/cursor_formatter.py"; _ps=("${PIPESTATUS[@]}"); } || true
    _rc="${_ps[0]}"
  else
    { "${cmd[@]}" --workspace "$PWD" --trust -p "$_initial_prompt" < /dev/null 2>&1 | tee "$_cursor_log"; _ps=("${PIPESTATUS[@]}"); } || true
    _rc="${_ps[0]}"
  fi

  # Auto-fallback: if the model's quota is exhausted, retry with --model auto
  if [[ "$_rc" -ne 0 ]] && _flowai_cursor_is_usage_exhausted "$_cursor_log"; then
    log_warn "⚡ Model '$model' usage exhausted — switching to Auto..."
    _rc=0
    local auto_cmd=("$_ca" --model auto --yolo)
    if [[ "${FLOWAI_AGENT_VERBOSE:-1}" == "1" ]]; then
      { "${auto_cmd[@]}" --workspace "$PWD" --trust --output-format stream-json "$_initial_prompt" < /dev/null 2>&1 | python3 "$FLOWAI_HOME/src/tools/cursor_formatter.py"; _ps=("${PIPESTATUS[@]}"); } || true
      _rc="${_ps[0]}"
    else
      { "${auto_cmd[@]}" --workspace "$PWD" --trust -p "$_initial_prompt" < /dev/null; _ps=("${PIPESTATUS[@]}"); } || true
      _rc="${_ps[0]}"
    fi
  fi
  rm -f "$_cursor_log"

  _c1="$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)"
  _cw=$((_c1 - _c0))
  flowai_debug_session_log "H-B" "cursor.sh:flowai_tool_cursor_run" "oneshot_phase_cursor_finished" \
    "{\"model\":\"${model}\",\"interactive\":false,\"cursor_wall_ms\":${_cw},\"prompt_bytes\":${_sz},\"exit\":${_rc}}"
  # endregion
  rm -f "$tmp_prompt"
  trap - EXIT
  return "$_rc"
}

# ─── Oneshot Function ────────────────────────────────────────────────────────

# Non-interactive single-shot invocation.
# Args: $1=model  $2=prompt_file
# Returns: raw LLM output on stdout.
flowai_tool_cursor_run_oneshot() {
  local model="$1"
  local prompt_file="$2"

  local _ca
  _ca="$(_flowai_cursor_resolve_executable)" || {
    log_warn "cursor-agent not installed — returning empty graph fragment." >&2
    printf '{"nodes":[],"edges":[],"insights":[]}'
    return 0
  }

  local prompt
  prompt="$(cat "$prompt_file")"

  local cmd=("$_ca")
  if [[ -n "$model" && "$model" != "default" ]]; then
    cmd+=(--model "$model")
  fi

  # region agent log
  local _c0 _c1 _cw _plen _rc=0
  _plen="${#prompt}"
  _c0="$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)"

  local _cursor_log
  _cursor_log="$(mktemp "${FLOWAI_DIR:-$PWD/.flowai}/cursor_oneshot_log_XXXXXX")"
  "${cmd[@]}" -p "$prompt" < /dev/null 2>"$_cursor_log" || _rc=$?

  # Auto-fallback: if the model's quota is exhausted, retry with --model auto
  if [[ "$_rc" -ne 0 ]] && _flowai_cursor_is_usage_exhausted "$_cursor_log"; then
    log_warn "⚡ Model '$model' usage exhausted — switching to Auto..." >&2
    _rc=0
    "$_ca" --model auto -p "$prompt" < /dev/null 2>/dev/null || _rc=$?
  fi
  rm -f "$_cursor_log"

  if [[ "$_rc" -ne 0 ]]; then
    echo '{}'
  fi
  _c1="$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)"
  _cw=$((_c1 - _c0))
  flowai_debug_session_log "H-B" "cursor.sh:flowai_tool_cursor_run_oneshot" "oneshot_cursor_finished" \
    "{\"model\":\"${model}\",\"cursor_wall_ms\":${_cw},\"prompt_chars\":${_plen},\"exit\":${_rc}}"
  # endregion
  return "$_rc"
}

