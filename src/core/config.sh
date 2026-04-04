#!/usr/bin/env bash
# Parses .flowai/config.json in the consumer project (run from repository root).
# shellcheck shell=bash

export FLOWAI_DIR="${FLOWAI_DIR:-$PWD/.flowai}"
export FLOWAI_CONFIG="${FLOWAI_DIR}/config.json"

flowai_cfg_read() {
  local jq_path="$1"
  local default_val="$2"
  if [[ ! -f "$FLOWAI_CONFIG" ]]; then
    printf '%s' "$default_val"
    return
  fi
  local val
  val="$(jq -r "$jq_path" "$FLOWAI_CONFIG" 2>/dev/null)" || val=""
  if [[ -z "$val" || "$val" == "null" ]]; then
    printf '%s' "$default_val"
  else
    printf '%s' "$val"
  fi
}

flowai_cfg_auto_approve() {
  flowai_cfg_read '.auto_approve' 'false'
}

flowai_cfg_layout() {
  flowai_cfg_read '.layout' 'dashboard'
}

# Role keys may contain hyphens — use jq --arg for safe lookup.
flowai_cfg_pipeline_role() {
  local phase="$1"
  local def="${2:-backend-engineer}"
  if [[ ! -f "$FLOWAI_CONFIG" ]]; then
    printf '%s' "$def"
    return
  fi
  jq -r --arg p "$phase" --arg d "$def" '.pipeline[$p] // $d' "$FLOWAI_CONFIG" 2>/dev/null || printf '%s' "$def"
}

flowai_cfg_role_tool() {
  local role="$1"
  local def="${2:-gemini}"
  if [[ ! -f "$FLOWAI_CONFIG" ]]; then
    printf '%s' "$def"
    return
  fi
  jq -r --arg r "$role" --arg d "$def" '.roles[$r].tool // $d' "$FLOWAI_CONFIG" 2>/dev/null || printf '%s' "$def"
}

flowai_cfg_role_model() {
  local role="$1"
  local def="${2:-}"
  if [[ ! -f "$FLOWAI_CONFIG" ]]; then
    printf '%s' "$def"
    return
  fi
  jq -r --arg r "$role" --arg d "$def" '.roles[$r].model // $d' "$FLOWAI_CONFIG" 2>/dev/null || printf '%s' "$def"
}

flowai_cfg_default_model() {
  flowai_cfg_read '.default_model' 'gpt-4o'
}
