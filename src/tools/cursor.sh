#!/usr/bin/env bash
# FlowAI Cursor Tool Plugin
# Defines the two required plugin API functions:
#   flowai_tool_cursor_print_models  — used by: flowai models list cursor
#   flowai_tool_cursor_run           — used by: ai.sh dispatcher
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

# Cursor has no headless CLI — print the enriched prompt for manual paste into Composer.
# Args: $1=model  $2=auto_approve  $3=run_interactive  $4=sys_prompt
# Note: model/auto_approve/run_interactive are accepted but unused (display-only tool).
flowai_tool_cursor_run() {
  local sys_prompt="$4"
  log_warn "Cursor selected — paste the following into Composer (Agent tab):"
  printf '%s\n' "$sys_prompt"
  return 0
}

# Cursor has no headless CLI — oneshot returns empty fallback.
# Args: $1=model  $2=prompt_file
flowai_tool_cursor_run_oneshot() {
  log_warn "Cursor does not support oneshot extraction — returning empty graph fragment." >&2
  printf '{"nodes":[],"edges":[],"insights":[]}'
}
