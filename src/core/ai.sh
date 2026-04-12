#!/usr/bin/env bash
# FlowAI — AI tool dispatcher.
# Loads all src/tools/*.sh plugins at source time and dispatches via
# flowai_tool_<name>_run(). To add a new tool: create the plugin file and
# add the catalog entry to models-catalog.json — this file never changes.
# shellcheck shell=bash

# shellcheck source=src/core/config.sh
source "$FLOWAI_HOME/src/core/config.sh"
# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"
# shellcheck source=src/core/skills.sh
source "$FLOWAI_HOME/src/core/skills.sh"
# shellcheck source=src/bootstrap/specify.sh
source "$FLOWAI_HOME/src/bootstrap/specify.sh"

for _flowai_tool_plugin in "$FLOWAI_HOME/src/tools/"*.sh; do
  [[ -f "$_flowai_tool_plugin" ]] || continue
  # shellcheck disable=SC1090
  source "$_flowai_tool_plugin"
done
unset _flowai_tool_plugin

# Resolve and validate the model id for a tool.
# Falls back to the catalog default_id and logs a warning on mismatch.
flowai_ai_resolve_model_for_tool() {
  local tool="$1"
  local raw="$2"

  if [[ -z "$raw" || "$raw" == "null" ]]; then
    flowai_cfg_default_model_for_tool "$tool"
    return
  fi

  if [[ "$tool" == "claude" ]]; then
    case "$raw" in
      gpt-*|o1|o1-*|o3|o3-*|chatgpt-*)
        local fb
        fb="$(flowai_cfg_default_model_for_tool claude)"
        log_warn "Model '$raw' is not valid for Claude Code — using '$fb'. Update roles.*.model in .flowai/config.json."
        printf '%s' "$fb"
        return
        ;;
    esac
  fi

  case "$tool" in
    claude|gemini)
      [[ "${FLOWAI_ALLOW_UNKNOWN_MODEL:-0}" == "1" ]] && { printf '%s' "$raw"; return; }
      if declare -F flowai_models_catalog_contains >/dev/null 2>&1 && flowai_models_catalog_contains "$tool" "$raw"; then
        printf '%s' "$raw"
        return
      fi
      local fb
      fb="$(flowai_cfg_default_model_for_tool "$tool")"
      log_warn "Model '$raw' is not in catalog for '$tool' — using '$fb'. Run: flowai models list $tool"
      printf '%s' "$fb"
      return
      ;;
  esac

  printf '%s' "$raw"
}

flowai_ai_run() {
  local phase="$1"
  local prompt_file="$2"
  local run_interactive="$3"

  local tool="" model="" role=""

  if [[ "$phase" == "master" ]]; then
    tool="$(flowai_cfg_read '.master.tool' 'gemini')"
    model="$(flowai_cfg_read '.master.model' '')"
  else
    role="$(flowai_cfg_pipeline_role "$phase" "backend-engineer")"
    tool="$(flowai_cfg_role_tool "$role" "")"
    model="$(flowai_cfg_role_model "$role" "")"
    if [[ -z "$tool" || "$tool" == "null" ]]; then
      tool="$(flowai_cfg_read '.master.tool' 'gemini')"
    fi
  fi
  model="$(flowai_ai_resolve_model_for_tool "$tool" "$model")"

  local auto_approve
  auto_approve="$(flowai_cfg_auto_approve)"

  local sys_prompt=""
  sys_prompt="$(flowai_skills_build_prompt "$phase" "$prompt_file")"

  log_header "Phase: $phase | Tool: $tool | Model: $model"

  local run_fn="flowai_tool_${tool}_run"
  if ! declare -F "$run_fn" >/dev/null 2>&1; then
    log_error "Unknown tool '$tool' — no ${run_fn}() found."
    log_error "Create src/tools/${tool}.sh with ${run_fn}() and add the tool to models-catalog.json."
    return 1
  fi

  "$run_fn" "$model" "$auto_approve" "$run_interactive" "$sys_prompt"
}

# Non-interactive single-shot AI invocation.
# Runs the prompt through the configured tool and prints the LLM response to stdout.
# Usage: output="$(flowai_ai_run_oneshot <phase> <prompt_file>)"
flowai_ai_run_oneshot() {
  local phase="$1"
  local prompt_file="$2"

  local tool="" model=""
  if [[ "$phase" == "master" ]]; then
    tool="$(flowai_cfg_read '.master.tool' 'gemini')"
    model="$(flowai_cfg_read '.master.model' '')"
  else
    local role
    role="$(flowai_cfg_pipeline_role "$phase" "backend-engineer")"
    tool="$(flowai_cfg_role_tool "$role" "")"
    model="$(flowai_cfg_role_model "$role" "")"
    if [[ -z "$tool" || "$tool" == "null" ]]; then
      tool="$(flowai_cfg_read '.master.tool' 'gemini')"
    fi
  fi
  model="$(flowai_ai_resolve_model_for_tool "$tool" "$model")"

  local run_fn="flowai_tool_${tool}_run_oneshot"
  if ! declare -F "$run_fn" >/dev/null 2>&1; then
    # Fail closed: if tool has no _run_oneshot, reject rather than silently approve
    log_warn "Tool '$tool' has no oneshot function — cannot perform AI validation."
    echo "VERDICT: REJECTED — tool '$tool' does not support one-shot review"
    return 1
  fi

  "$run_fn" "$model" "$prompt_file"
}
