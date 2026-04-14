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

# Brief constraint reminder appended to the END of the prompt context.
# Combined with HARD CONSTRAINTS at the TOP of the system prompt, this
# creates a "sandwich" reinforcement — LLMs weight both the beginning and end
# of the context window more heavily than the middle.
readonly _FLOWAI_CURSOR_CONSTRAINT_REMINDER="REMINDER — MANDATORY RULES (from PIPELINE COORDINATION):
1. You may ONLY write to the OUTPUT FILE in your PIPELINE DIRECTIVE. Do NOT create *_REVIEW.md, *_PLAN.md, *_SUMMARY.md, *_REPORT.md or any other files.
2. If a knowledge graph is available, read GRAPH_REPORT.md BEFORE using search, find, or grep.
3. spec.md is the single source of truth. Verify alignment before completing work."

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
  printf '\n%s\n' "$_FLOWAI_CURSOR_CONSTRAINT_REMINDER"
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
    printf '%s\n' "$_FLOWAI_CURSOR_CONSTRAINT_REMINDER"
  } > "$tmp_prompt"

  local abs_prompt
  abs_prompt="$(cd "$(dirname "$tmp_prompt")" && pwd)/$(basename "$tmp_prompt")"

  local cmd=("$_ca")
  # Model selection
  if [[ -n "$model" && "$model" != "default" ]]; then
    cmd+=(--model "$model")
  fi

  # Review: Ask mode (no edits) — parity with Claude review restrictions.
  # Else: --yolo when non-interactive or auto-approve (no stdin to approve).
  if [[ "${FLOWAI_CURRENT_PHASE:-}" == "review" ]]; then
    cmd+=(--mode ask)
  elif [[ "$run_interactive" == "false" ]] || [[ "$auto_approve" == "true" ]]; then
    cmd+=(--yolo)
  fi

  local _initial_prompt="Your complete PIPELINE DIRECTIVE, HARD CONSTRAINTS, skills, and STAGED WORKFLOW are in this file — read it fully before acting: ${abs_prompt}

You are inside a FlowAI pipeline phase. Follow the STAGED WORKFLOW exactly as written — begin with step 1 now. Do NOT deviate from the directive."

  if [[ "$run_interactive" == "true" ]]; then
    "${cmd[@]}" "$_initial_prompt" || return $?
    rm -f "$tmp_prompt"
    trap - EXIT
    return 0
  fi

  # Non-interactive: -p print mode; < /dev/null so the agent exits after work.
  # Per Cursor docs, combine --print with --yolo (added above) so edits are applied.
  # --trust and explicit --workspace are only valid with --print; interactive Master
  # uses the REPL path without -p and must not pass --trust (CLI error otherwise).
  "${cmd[@]}" --workspace "$PWD" --trust -p "$_initial_prompt" < /dev/null || return $?
  rm -f "$tmp_prompt"
  trap - EXIT
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

  "${cmd[@]}" -p "$prompt" < /dev/null 2>/dev/null || echo '{}'
}
