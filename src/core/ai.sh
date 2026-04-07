#!/usr/bin/env bash
# FlowAI — AI tool runner — keeps CLI quirks in one place.
# shellcheck shell=bash

# shellcheck source=src/core/config.sh
source "$FLOWAI_HOME/src/core/config.sh"
# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"
# shellcheck source=src/core/skills.sh
source "$FLOWAI_HOME/src/core/skills.sh"
# shellcheck source=src/bootstrap/specify.sh
source "$FLOWAI_HOME/src/bootstrap/specify.sh"

flowai_ai_run() {
  local phase="$1"
  local prompt_file="$2"
  local run_interactive="$3"

  local tool=""
  local model=""
  local role=""

  if [[ "$phase" == "master" ]]; then
    tool="$(flowai_cfg_read '.master.tool' 'gemini')"
    model="$(flowai_cfg_read '.master.model' 'gpt-4o')"
  else
    role="$(flowai_cfg_pipeline_role "$phase" "backend-engineer")"
    tool="$(flowai_cfg_role_tool "$role" "")"
    model="$(flowai_cfg_role_model "$role" "")"
    if [[ -z "$tool" || "$tool" == "null" ]]; then
      tool="$(flowai_cfg_read '.master.tool' 'gemini')"
    fi
    if [[ -z "$model" || "$model" == "null" ]]; then
      model="$(flowai_cfg_default_model)"
    fi
  fi

  local auto_approve
  auto_approve="$(flowai_cfg_auto_approve)"

  # Build enriched system prompt: role + skills + constitution
  local sys_prompt=""
  sys_prompt="$(flowai_skills_build_prompt "$phase" "$prompt_file")"

  log_header "Role: $phase | Tool: $tool | Model: $model"

  local cmd=()
  case "$tool" in
    gemini)
      cmd=(gemini -m "$model")
      if [[ "$auto_approve" == "true" || "$run_interactive" == "false" ]]; then
        cmd+=(-y)
      fi
      ;;
    claude)
      cmd=(claude --model "$model")
      # Attach MCP config if available
      if [[ -f "$FLOWAI_DIR/mcp.json" ]]; then
        cmd+=(--mcp-config "$FLOWAI_DIR/mcp.json")
      fi
      if [[ "$auto_approve" == "true" && "$run_interactive" == "false" ]]; then
        cmd+=(--dangerously-skip-permissions)
      fi
      ;;
    cursor)
      log_warn "Cursor selected — paste the following into Composer:"
      printf '%s\n' "$sys_prompt"
      return 0
      ;;
    *)
      log_error "Unknown tool: $tool"
      return 1
      ;;
  esac

  if [[ "$run_interactive" == "true" ]]; then
    "${cmd[@]}" || return $?
    return 0
  fi

  if [[ "$tool" == "claude" ]]; then
    "${cmd[@]}" -p "$sys_prompt" < /dev/null || return $?
  else
    # shellcheck disable=SC2145
    "${cmd[@]}" "$sys_prompt" < /dev/null || return $?
  fi
}
