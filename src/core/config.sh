#!/usr/bin/env bash
# Reads .flowai/config.json from the consumer project root.
# shellcheck shell=bash

export FLOWAI_DIR="${FLOWAI_DIR:-$PWD/.flowai}"
export FLOWAI_CONFIG="${FLOWAI_DIR}/config.json"

# Normalize CRLF → LF in config.json (Windows-only).
# Git Bash / MSYS write CRLF which breaks jq value extraction.
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    if [[ -f "$FLOWAI_CONFIG" ]]; then
      sed 's/\r$//' "$FLOWAI_CONFIG" > "${FLOWAI_CONFIG}.tmp" 2>/dev/null \
        && mv -f "${FLOWAI_CONFIG}.tmp" "$FLOWAI_CONFIG" 2>/dev/null \
        || rm -f "${FLOWAI_CONFIG}.tmp" 2>/dev/null
    fi
    ;;
esac

# shellcheck disable=SC1091
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
  local def="${2:-gemini}"
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
#   2. .default_model               in config.json   (gemini legacy key)
#   3. .claude_default_model        in config.json   (claude legacy key)
#   4. .tools.<tool>.default_id     in models-catalog.json
#
# Adding a new tool to models-catalog.json gives it a working default with no
# changes to this file.
flowai_cfg_default_model_for_tool() {
  local tool="${1:-}"
  [[ -z "$tool" ]] && return 0

  # 1. Generic per-tool override in project config
  local override=""
  if [[ -f "$FLOWAI_CONFIG" ]]; then
    override="$(jq -r --arg t "$tool" '.tool_defaults[$t].model // empty' "$FLOWAI_CONFIG" 2>/dev/null | tr -d '\r')"
  fi
  if [[ -n "$override" && "$override" != "null" ]]; then
    printf '%s' "$override"
    return
  fi

  # 2–3. Legacy single-key overrides (backward compatibility)
  if [[ "$tool" == "gemini" ]]; then
    local v=""
    v="$(flowai_cfg_read '.default_model' '')"
    [[ -n "$v" ]] && { printf '%s' "$v"; return; }
  fi
  if [[ "$tool" == "claude" ]]; then
    local v=""
    v="$(flowai_cfg_read '.claude_default_model' '')"
    [[ -n "$v" ]] && { printf '%s' "$v"; return; }
  fi

  # 4. Catalog default_id
  if declare -F flowai_models_catalog_default_for_tool >/dev/null 2>&1; then
    local catalog=""
    catalog="$(flowai_models_catalog_default_for_tool "$tool")"
    [[ -n "$catalog" ]] && { printf '%s' "$catalog"; return; }
  fi

  return 0
}

# Shims for legacy call-sites — delegate to the generic resolver.
flowai_cfg_default_model()        { flowai_cfg_default_model_for_tool "gemini"; }
flowai_cfg_claude_default_model() { flowai_cfg_default_model_for_tool "claude"; }
