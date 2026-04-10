#!/usr/bin/env bash
# FlowAI Copilot Tool Plugin
# Defines the two required plugin API functions:
#   flowai_tool_copilot_print_models  — used by: flowai models list copilot
#   flowai_tool_copilot_run           — used by: ai.sh dispatcher
# shellcheck shell=bash

flowai_tool_copilot_print_models() {
  # _flowai_print_tool_block is dynamically provided by the caller (models.sh)
  _flowai_print_tool_block "copilot"
}

# Copilot has no headless CLI — print the enriched prompt for manual paste into Copilot Chat.
# Args: $1=model  $2=auto_approve  $3=run_interactive  $4=sys_prompt
# Note: model/auto_approve/run_interactive are accepted but unused (display-only tool).
flowai_tool_copilot_run() {
  local sys_prompt="$4"
  log_warn "Copilot selected — paste the following into GitHub Copilot Chat (no headless CLI available):"
  printf '%s\n' "$sys_prompt"
  return 0
}

# Copilot has no headless CLI — oneshot returns empty fallback.
# Args: $1=model  $2=prompt_file
flowai_tool_copilot_run_oneshot() {
  log_warn "Copilot does not support oneshot extraction — returning empty graph fragment." >&2
  printf '{"nodes":[],"edges":[],"insights":[]}'
}
