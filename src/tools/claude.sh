#!/usr/bin/env bash
# FlowAI Claude Tool Plugin
# Defines the two required plugin API functions:
#   flowai_tool_claude_print_models  — used by: flowai models list claude
#   flowai_tool_claude_run           — used by: ai.sh dispatcher
# shellcheck shell=bash

flowai_tool_claude_print_models() {
  # _flowai_print_tool_block is dynamically provided by the caller (models.sh)
  _flowai_print_tool_block "claude"
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

  if [[ "$auto_approve" == "true" && "$run_interactive" == "false" ]]; then
    cmd+=(--dangerously-skip-permissions)
  fi

  if [[ "$run_interactive" == "true" ]]; then
    "${cmd[@]}" --system-prompt "$sys_prompt" || return $?
    return 0
  fi

  "${cmd[@]}" --system-prompt "$sys_prompt" -p "Execute the pipeline directive in your system prompt. Begin immediately." < /dev/null || return $?
}

# Non-interactive single-shot invocation for graph semantic extraction.
# Args: $1=model  $2=prompt_file
# Returns: raw LLM output on stdout.
flowai_tool_claude_run_oneshot() {
  local model="$1"
  local prompt_file="$2"
  local prompt
  prompt="$(cat "$prompt_file")"

  claude --model "$model" --system-prompt "You are a knowledge graph extraction engine. Return ONLY valid JSON. No markdown fences, no explanation." -p "$prompt" < /dev/null 2>/dev/null || echo '{}'
}
