#!/usr/bin/env bash
# FlowAI Copilot Tool Plugin
# Defines the two required plugin API functions:
#   flowai_tool_copilot_print_models  — used by: flowai models list copilot
#   flowai_tool_copilot_run           — used by: ai.sh dispatcher
# shellcheck shell=bash

# Inject FlowAI rules into .github/copilot-instructions.md for Copilot propagation.
# GitHub Copilot reads copilot-instructions.md for project-level custom instructions.
# Args: $1=content (tool-agnostic rules from flowai_ai_project_config_content)
flowai_tool_copilot_inject_project_config() {
  local content="$1"
  local marker_start="<!-- FLOWAI:START -->"
  local marker_end="<!-- FLOWAI:END -->"
  local gh_dir="$PWD/.github"
  local copilot_md="$gh_dir/copilot-instructions.md"
  local block="${marker_start}
${content}
${marker_end}"

  mkdir -p "$gh_dir"
  if [[ -f "$copilot_md" ]]; then
    local cleaned
    cleaned="$(sed "/${marker_start}/,/${marker_end}/d" "$copilot_md")"
    printf '%s\n\n%s\n' "$cleaned" "$block" > "$copilot_md"
  else
    printf '%s\n' "$block" > "$copilot_md"
  fi
}

flowai_tool_copilot_print_models() {
  # _flowai_print_tool_block is dynamically provided by the caller (models.sh)
  _flowai_print_tool_block "copilot"
}

# Plugin API: Copilot is always paste-only (no headless CLI).
flowai_tool_copilot_is_paste_only() { return 0; }

# Copilot has no headless CLI — print the enriched prompt for manual paste into Copilot Chat.
# Args: $1=model  $2=auto_approve  $3=run_interactive  $4=sys_prompt
# Note: model/auto_approve/run_interactive are accepted but unused (display-only tool).
flowai_tool_copilot_run() {
  local sys_prompt="$4"
  log_warn "Copilot selected — paste the following into GitHub Copilot Chat (no headless CLI available):"
  printf '%s\n' "$sys_prompt"
  printf '\n%s\n' "${FLOWAI_CONSTRAINT_REMINDER:-}"
  return 0
}

# Copilot has no headless CLI — oneshot returns empty fallback.
# Args: $1=model  $2=prompt_file
flowai_tool_copilot_run_oneshot() {
  log_warn "Copilot does not support oneshot extraction — returning empty graph fragment." >&2
  printf '{"nodes":[],"edges":[],"insights":[]}'
}
