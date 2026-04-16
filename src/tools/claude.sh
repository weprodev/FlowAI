#!/usr/bin/env bash
# FlowAI Claude Tool Plugin
# shellcheck source=src/core/debug_session.sh
source "$FLOWAI_HOME/src/core/debug_session.sh"
# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"
# Defines the two required plugin API functions:
#   flowai_tool_claude_print_models  — used by: flowai models list claude
#   flowai_tool_claude_run           — used by: ai.sh dispatcher
# shellcheck shell=bash

# Inject FlowAI rules into .claude/CLAUDE.md for subagent propagation.
# Claude Code's --system-prompt does NOT propagate to Agent subagents —
# CLAUDE.md is the ONLY mechanism auto-discovered by all Claude sessions.
# Args: $1=content (tool-agnostic rules from flowai_ai_project_config_content)
flowai_tool_claude_inject_project_config() {
  local content="$1"
  local marker_start="<!-- FLOWAI:START -->"
  local marker_end="<!-- FLOWAI:END -->"
  local claude_dir="$PWD/.claude"
  local claude_md="$claude_dir/CLAUDE.md"
  local block="${marker_start}
${content}
${marker_end}"

  mkdir -p "$claude_dir"
  if [[ -f "$claude_md" ]]; then
    local cleaned
    cleaned="$(sed "/${marker_start}/,/${marker_end}/d" "$claude_md")"
    printf '%s\n\n%s\n' "$cleaned" "$block" > "$claude_md"
  else
    printf '%s\n' "$block" > "$claude_md"
  fi
}

# Claude Code captures terminal control sequences, breaking gum's arrow-key
# navigation. Return 1 to disable gum in Claude panes.
flowai_tool_claude_supports_gum() { return 1; }

flowai_tool_claude_print_models() {
  # _flowai_print_tool_block is dynamically provided by the caller (models.sh)
  _flowai_print_tool_block "claude"
}

# Validate model ID for Claude Code. Rejects models from other providers.
# Args: $1=raw model ID
# Prints: validated model ID (or fallback)
flowai_tool_claude_validate_model() {
  local raw="$1"
  case "$raw" in
    gpt-*|o1|o1-*|o3|o3-*|chatgpt-*)
      local fb
      fb="$(flowai_cfg_default_model_for_tool claude)"
      log_warn "Model '$raw' is not valid for Claude Code — using '$fb'. Update roles.*.model in .flowai/config.json."
      printf '%s' "$fb"
      return
      ;;
  esac
  [[ "${FLOWAI_ALLOW_UNKNOWN_MODEL:-0}" == "1" ]] && { printf '%s' "$raw"; return; }
  if declare -F flowai_models_catalog_contains >/dev/null 2>&1 && flowai_models_catalog_contains "claude" "$raw"; then
    printf '%s' "$raw"
    return
  fi
  local fb
  fb="$(flowai_cfg_default_model_for_tool claude)"
  if [[ "$fb" != "$raw" ]]; then
    log_warn "Model '$raw' is not in catalog for Claude — using '$fb'. Run: flowai models list claude"
  fi
  printf '%s' "$fb"
}

# Execute a prompt against the Claude Code CLI.
# Args: $1=model  $2=auto_approve  $3=run_interactive  $4=sys_prompt
# Reads: FLOWAI_DIR (for optional mcp.json)
flowai_tool_claude_run() {
  local model="$1"
  local auto_approve="$2"
  local run_interactive="$3"
  local sys_prompt="$4"

  local cmd=(claude --model "$model")

  # Attach MCP config if available
  if [[ -f "${FLOWAI_DIR}/mcp.json" ]]; then
    cmd+=(--mcp-config "${FLOWAI_DIR}/mcp.json")
  fi

  # Permission handling:
  # - "acceptEdits" auto-approves file reads/writes without the scary
  #   "Bypass Permissions" warning that frightens users.
  # - Non-interactive phases NEED auto-approval because there's no stdin
  #   to grant permissions — without this, Claude silently fails to write files.
  # - Interactive phases use acceptEdits when auto_approve is configured,
  #   otherwise default (user approves each action).
  if [[ "$run_interactive" == "false" ]] || [[ "$auto_approve" == "true" ]]; then
    cmd+=(--permission-mode acceptEdits)
  fi

  # Append constraint reminder to the end of Claude's context (sandwich reinforcement)
  cmd+=(--append-system-prompt "${FLOWAI_CONSTRAINT_REMINDER:-}")

  # Initial prompt that anchors the agent to the pipeline workflow.
  # Without this, Claude ignores the system prompt and responds to user input freely.
  local _initial_prompt="Read your PIPELINE DIRECTIVE and HARD CONSTRAINTS in the system prompt. You are inside a FlowAI pipeline phase. Follow the STAGED WORKFLOW exactly as written — begin with step 1 now. Do NOT deviate from the directive."

  # region agent log
  local _cl0 _cl1 _clw _sz _rc=0
  _sz="${#sys_prompt}"

  if [[ "$run_interactive" == "true" ]]; then
    # Interactive: user can chat with the agent after it starts.
    # Passing a prompt argument without -p keeps the session interactive.
    _cl0="$(date +%s)000"
    "${cmd[@]}" --system-prompt "$sys_prompt" "$_initial_prompt" || _rc=$?
    _cl1="$(date +%s)000"
    _clw=$((_cl1 - _cl0))
    flowai_debug_session_log "H-B" "claude.sh:flowai_tool_claude_run" "interactive_claude_finished" \
      "{\"model\":\"${model}\",\"interactive\":true,\"claude_wall_ms\":${_clw},\"prompt_chars\":${_sz},\"exit\":${_rc}}"
    return "$_rc"
  fi

  # Non-interactive: agent runs autonomously then MUST exit so the phase run
  # loop can verify the artifact and show the approval gate.
  #
  # Approach: -p (print mode) guarantees clean exit after completion.
  # Without -p, Claude Code's REPL may not exit even with stdin=/dev/null,
  # which blocks the approval gate and freezes the pipeline.
  #
  # For progress visibility: stream-json + formatter (same pattern as Gemini/Cursor).
  # When FLOWAI_AGENT_VERBOSE=1 (default), use stream-json with a Python formatter
  # so the tmux pane shows real-time tool calls and reasoning.
  _cl0="$(date +%s)000"
  local _claude_formatter="$FLOWAI_HOME/src/tools/claude_formatter.py"
  if [[ "${FLOWAI_AGENT_VERBOSE:-1}" == "1" ]] && command -v python3 >/dev/null 2>&1 \
     && [[ -f "$_claude_formatter" ]]; then
    "${cmd[@]}" --system-prompt "$sys_prompt" \
      -p --output-format stream-json --verbose "$_initial_prompt" \
      < /dev/null 2>&1 | python3 "$_claude_formatter" || _rc=$?
  else
    "${cmd[@]}" --system-prompt "$sys_prompt" -p "$_initial_prompt" < /dev/null || _rc=$?
  fi
  _cl1="$(date +%s)000"
  _clw=$((_cl1 - _cl0))
  flowai_debug_session_log "H-B" "claude.sh:flowai_tool_claude_run" "oneshot_phase_claude_finished" \
    "{\"model\":\"${model}\",\"interactive\":false,\"claude_wall_ms\":${_clw},\"prompt_chars\":${_sz},\"exit\":${_rc}}"
  # endregion
  return "$_rc"
}

# Non-interactive single-shot invocation.
# Args: $1=model  $2=prompt_file
# Returns: raw LLM output on stdout.
#
# The prompt file contains the full context (role + directive + artifact boundary
# + graph context). It is passed as the user message; a minimal system prompt
# instructs Claude to follow the directive precisely.
flowai_tool_claude_run_oneshot() {
  local model="$1"
  local prompt_file="$2"
  local prompt
  prompt="$(cat "$prompt_file")"

  # region agent log
  local _cl0 _cl1 _clw _plen _rc=0
  _plen="${#prompt}"
  _cl0="$(date +%s)000"
  claude --model "$model" \
    --system-prompt "Follow the directive in the user message precisely. Produce only the requested output." \
    -p "$prompt" < /dev/null 2>/dev/null || _rc=$?
  if [[ "$_rc" -ne 0 ]]; then
    echo '{}'
  fi
  _cl1="$(date +%s)000"
  _clw=$((_cl1 - _cl0))
  flowai_debug_session_log "H-B" "claude.sh:flowai_tool_claude_run_oneshot" "oneshot_claude_finished" \
    "{\"model\":\"${model}\",\"claude_wall_ms\":${_clw},\"prompt_chars\":${_plen},\"exit\":${_rc}}"
  # endregion
  return "$_rc"
}
