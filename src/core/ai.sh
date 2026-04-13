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
# shellcheck source=src/core/debug_session.sh
source "$FLOWAI_HOME/src/core/debug_session.sh"
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

# Helper: resolve exactly which tool and model will run for a specific phase
flowai_ai_resolve_tool_and_model_for_phase() {
  local phase="$1"
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
  echo "$tool:$model"
}

# Tools with no in-tmux REPL — only print a prompt for paste into an IDE (Cursor, Copilot Chat, etc.).
flowai_ai_tool_is_paste_only() {
  case "$1" in
    cursor|copilot) return 0 ;;
    *) return 1 ;;
  esac
}

# ─── Tool Project Config Injection ───────────────────────────────────────────
# Tool-agnostic content for project config injection. This is the SHARED content
# that every tool's project config should contain. Each tool plugin implements
# flowai_tool_<name>_inject_project_config() with the tool-specific file format
# and location (e.g., CLAUDE.md, .cursorrules, copilot-instructions.md).
#
# Usage: content="$(flowai_ai_project_config_content)"
flowai_ai_project_config_content() {
  cat <<'RULES'
# FlowAI Pipeline Rules (auto-generated — do not edit between markers)

## MANDATORY: Knowledge Graph Navigation
A compiled knowledge graph of this codebase is available at `.flowai/wiki/`.

**You MUST follow this order:**
1. BEFORE any file search, grep, find, or Bash exploration: READ `.flowai/wiki/GRAPH_REPORT.md`
2. Use `.flowai/wiki/index.md` to locate the exact wiki page for any concept
3. Use `.flowai/wiki/graph.json` for multi-hop reasoning (dependencies, call chains)
4. ONLY after the graph points you to a specific file should you read that file
5. Do NOT explore the codebase blindly — the graph exists to prevent that

**PROHIBITED:** Do NOT run find, grep, rg, or broad file searches to understand
the codebase. The graph already contains this information. Read the graph first.

## MANDATORY: Artifact Boundaries
When operating inside a FlowAI pipeline phase:
- You may ONLY write to the OUTPUT FILE specified in the PIPELINE DIRECTIVE
- Do NOT create *_REVIEW.md, *_PLAN.md, *_SUMMARY.md, *_REPORT.md or any other files
- spec.md is the single source of truth — verify alignment before completing work
RULES
}

# Inject project config into ALL tools that provide _inject_project_config().
# Called from start.sh when a knowledge graph exists. Each tool plugin handles
# its own file format and location — this function is the tool-agnostic dispatcher.
flowai_ai_inject_all_tool_configs() {
  local content
  content="$(flowai_ai_project_config_content)"

  local tool inject_fn
  for tool_plugin in "$FLOWAI_HOME/src/tools/"*.sh; do
    tool="$(basename "$tool_plugin" .sh)"
    inject_fn="flowai_tool_${tool}_inject_project_config"
    if declare -F "$inject_fn" >/dev/null 2>&1; then
      "$inject_fn" "$content"
    fi
  done
}

flowai_ai_run() {
  local phase="$1"
  local prompt_file="$2"
  local run_interactive="$3"

  local resolved
  resolved="$(flowai_ai_resolve_tool_and_model_for_phase "$phase")"
  local tool="${resolved%%:*}"
  local model="${resolved#*:}"

  local auto_approve
  auto_approve="$(flowai_cfg_auto_approve)"

  local sys_prompt=""
  # region agent log
  local _t_skills_0 _t_skills_1 _skills_ms
  _t_skills_0="$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)"
  sys_prompt="$(flowai_skills_build_prompt "$phase" "$prompt_file")"
  _t_skills_1="$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)"
  _skills_ms=$((_t_skills_1 - _t_skills_0))
  flowai_debug_session_log "H-A" "ai.sh:flowai_ai_run" "after_flowai_skills_build_prompt" \
    "{\"phase\":\"${phase}\",\"tool\":\"${tool}\",\"model\":\"${model}\",\"prompt_build_ms\":${_skills_ms},\"prompt_chars\":${#sys_prompt}}"
  # endregion

  log_header "Phase: $phase | Tool: $tool | Model: $model"

  local run_fn="flowai_tool_${tool}_run"
  if ! declare -F "$run_fn" >/dev/null 2>&1; then
    log_error "Unknown tool '$tool' — no ${run_fn}() found."
    log_error "Create src/tools/${tool}.sh with ${run_fn}() and add the tool to models-catalog.json."
    return 1
  fi

  # Export phase so tool plugins can apply phase-specific restrictions
  # (e.g., disallow Write for review phase, restrict artifact paths).
  FLOWAI_CURRENT_PHASE="$phase" "$run_fn" "$model" "$auto_approve" "$run_interactive" "$sys_prompt"
}

# Non-interactive single-shot AI invocation.
# Runs the prompt through the configured tool and prints the LLM response to stdout.
# Enriches the prompt with knowledge graph context when available (cheap navigation
# layer that reduces token usage on codebase exploration within the oneshot).
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

  # Enrich prompt with knowledge graph context when available.
  # The graph block is ~25 lines — small token cost for significant quality gain:
  # agents navigate via the compiled graph instead of exploring files blindly.
  local enriched_prompt="$prompt_file"
  if declare -F flowai_graph_is_enabled >/dev/null 2>&1 \
     && flowai_graph_is_enabled && flowai_graph_exists; then
    local graph_block
    graph_block="$(flowai_graph_context_block)"
    if [[ -n "$graph_block" ]]; then
      enriched_prompt="$(mktemp "${TMPDIR:-/tmp}/flowai_oneshot_enriched_XXXXXX")"
      { cat "$prompt_file"; printf '%s\n' "$graph_block"; } > "$enriched_prompt"
    fi
  fi

  local run_fn="flowai_tool_${tool}_run_oneshot"
  if ! declare -F "$run_fn" >/dev/null 2>&1; then
    # Fail closed: if tool has no _run_oneshot, reject rather than silently approve
    log_warn "Tool '$tool' has no oneshot function — cannot perform AI validation."
    echo "VERDICT: REJECTED — tool '$tool' does not support one-shot review"
    [[ "$enriched_prompt" != "$prompt_file" ]] && rm -f "$enriched_prompt" 2>/dev/null
    return 1
  fi

  "$run_fn" "$model" "$enriched_prompt"
  local rc=$?
  [[ "$enriched_prompt" != "$prompt_file" ]] && rm -f "$enriched_prompt" 2>/dev/null
  return $rc
}
