#!/usr/bin/env bash
# FlowAI Gemini Tool Plugin
# Defines the two required plugin API functions:
#   flowai_tool_gemini_print_models  — used by: flowai models list gemini
#   flowai_tool_gemini_run           — used by: ai.sh dispatcher
# shellcheck shell=bash

flowai_tool_gemini_print_models() {
  # _flowai_print_tool_block is dynamically provided by the caller (models.sh)
  _flowai_print_tool_block "gemini"
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
    "${cmd[@]}" || return $?
    return 0
  fi

  # shellcheck disable=SC2145
  "${cmd[@]}" "$sys_prompt" < /dev/null || return $?
}

# Non-interactive single-shot invocation for graph semantic extraction.
# Args: $1=model  $2=prompt_file
# Returns: raw LLM output on stdout.
flowai_tool_gemini_run_oneshot() {
  local model="$1"
  local prompt_file="$2"
  local prompt
  prompt="$(cat "$prompt_file")"

  gemini -m "$model" "$prompt" < /dev/null 2>/dev/null || echo '{}'
}
