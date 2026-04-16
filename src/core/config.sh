#!/usr/bin/env bash
# Reads .flowai/config.json from the consumer project root.
# shellcheck shell=bash

export FLOWAI_DIR="${FLOWAI_DIR:-$PWD/.flowai}"
export FLOWAI_CONFIG="${FLOWAI_DIR}/config.json"

# shellcheck source=src/core/models-catalog.sh
[[ -n "${FLOWAI_HOME:-}" ]] && source "$FLOWAI_HOME/src/core/models-catalog.sh"

# Reject absolute paths and ".." segments so stored paths cannot escape $PWD at read time.
flowai_validate_repo_rel_path() {
  local p="${1:-}"
  [[ -z "$p" ]] && return 1
  [[ "$p" == /* ]] && return 1
  local IFS='/'
  local -a parts=()
  read -ra parts <<< "$p"
  local seg
  for seg in "${parts[@]}"; do
    [[ -z "$seg" ]] && continue
    [[ "$seg" == "." ]] && continue
    [[ "$seg" == ".." ]] && return 1
  done
  return 0
}

# Strip leading "./" for stable storage and comparison.
flowai_normalize_repo_rel_path() {
  local p="${1:-}"
  while [[ "$p" == ./* ]]; do p="${p#./}"; done
  if [[ -z "$p" ]]; then
    printf '.'
  else
    printf '%s' "$p"
  fi
}

# Read a jq path from config.json, returning default_val when absent or null.
flowai_cfg_read() {
  local jq_path="$1"
  local default_val="$2"
  if [[ ! -f "$FLOWAI_CONFIG" ]]; then
    printf '%s' "$default_val"
    return
  fi
  local val
  val="$(jq -r "$jq_path" "$FLOWAI_CONFIG" 2>/dev/null | tr -d '\r')" || val=""
  if [[ -z "$val" || "$val" == "null" ]]; then
    printf '%s' "$default_val"
  else
    printf '%s' "$val"
  fi
}

flowai_cfg_auto_approve() { flowai_cfg_read '.auto_approve' 'false'; }
flowai_cfg_layout()       { flowai_cfg_read '.layout' 'dashboard'; }

# Git integration branch chosen at `flowai init` (main / master / develop).
flowai_cfg_default_branch() { flowai_cfg_read '.default_branch' 'main'; }

# Role keys may contain hyphens — use jq --arg for safe lookup.
flowai_cfg_pipeline_role() {
  local phase="$1"
  local def="${2:-backend-engineer}"
  if [[ ! -f "$FLOWAI_CONFIG" ]]; then
    printf '%s' "$def"
    return
  fi
  jq -r --arg p "$phase" --arg d "$def" '.pipeline[$p] // $d' "$FLOWAI_CONFIG" 2>/dev/null | tr -d '\r' || printf '%s' "$def"
}

flowai_cfg_role_tool() {
  local role="$1"
  local def="${2:-}"
  if [[ ! -f "$FLOWAI_CONFIG" ]]; then
    printf '%s' "$def"
    return
  fi
  jq -r --arg r "$role" --arg d "$def" '.roles[$r].tool // $d' "$FLOWAI_CONFIG" 2>/dev/null | tr -d '\r' || printf '%s' "$def"
}

flowai_cfg_role_model() {
  local role="$1"
  local def="${2:-}"
  if [[ ! -f "$FLOWAI_CONFIG" ]]; then
    printf '%s' "$def"
    return
  fi
  jq -r --arg r "$role" --arg d "$def" '.roles[$r].model // $d' "$FLOWAI_CONFIG" 2>/dev/null | tr -d '\r' || printf '%s' "$def"
}

# Resolve the default model for a tool.
#
# Resolution order (first non-empty value wins):
#   1. .tool_defaults.<tool>.model  in config.json   (generic; works for any tool)
#   2. .tools.<tool>.default_id     in models-catalog.json
#
# Adding a new tool to models-catalog.json gives it a working default with no
# changes to this file. Fully tool-agnostic — no tool names in this function.
flowai_cfg_default_model_for_tool() {
  local tool="${1:-}"
  [[ -z "$tool" ]] && return 0

  # 1. Per-tool override in project config
  local override=""
  if [[ -f "$FLOWAI_CONFIG" ]]; then
    override="$(jq -r --arg t "$tool" '.tool_defaults[$t].model // empty' "$FLOWAI_CONFIG" 2>/dev/null | tr -d '\r')"
  fi
  if [[ -n "$override" && "$override" != "null" ]]; then
    printf '%s' "$override"
    return
  fi

  # 2. Legacy config keys (backward compatibility for existing config.json files)
  # Reads <tool>_default_model or default_model from config — tool-agnostic lookup.
  if [[ -f "$FLOWAI_CONFIG" ]]; then
    local legacy=""
    legacy="$(jq -r --arg t "$tool" '
      .[$t + "_default_model"] // .default_model // empty
    ' "$FLOWAI_CONFIG" 2>/dev/null | tr -d '\r')"
    [[ -n "$legacy" && "$legacy" != "null" ]] && { printf '%s' "$legacy"; return; }
  fi

  # 3. Catalog default_id (single source of truth for defaults)
  if declare -F flowai_models_catalog_default_for_tool >/dev/null 2>&1; then
    local catalog=""
    catalog="$(flowai_models_catalog_default_for_tool "$tool")"
    [[ -n "$catalog" ]] && { printf '%s' "$catalog"; return; }
  fi

  return 0
}
