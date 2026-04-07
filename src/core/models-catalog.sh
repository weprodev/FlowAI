#!/usr/bin/env bash
# Valid model ids per FlowAI tool — loaded from repo root models-catalog.json (next to bin/, src/).
# shellcheck shell=bash

flowai_models_catalog_path() {
  printf '%s' "${FLOWAI_HOME}/models-catalog.json"
}

# Echo default model id for tool (claude | gemini), or empty if catalog missing/invalid.
flowai_models_catalog_default_for_tool() {
  local tool="$1"
  local f
  f="$(flowai_models_catalog_path)"
  [[ -f "$f" ]] || return 0
  jq -r --arg t "$tool" '.tools[$t].default_id // empty' "$f" 2>/dev/null
}

# One model id per line for tool.
flowai_models_catalog_ids_for_tool() {
  local tool="$1"
  local f
  f="$(flowai_models_catalog_path)"
  [[ -f "$f" ]] || return 0
  jq -r --arg t "$tool" '.tools[$t].models[]?.id // empty' "$f" 2>/dev/null
}

# Document URL for tool (for CLI hints).
flowai_models_catalog_doc_for_tool() {
  local tool="$1"
  local f
  f="$(flowai_models_catalog_path)"
  [[ -f "$f" ]] || return 0
  jq -r --arg t "$tool" '.tools[$t].doc // empty' "$f" 2>/dev/null
}

# Exit 0 if .tools.<tool> exists in the catalog.
flowai_models_catalog_has_tool() {
  local tool="$1"
  local f
  f="$(flowai_models_catalog_path)"
  [[ -f "$f" ]] || return 1
  [[ -n "$tool" ]] || return 1
  jq -e --arg t "$tool" '.tools | has($t)' "$f" >/dev/null 2>&1
}

# Exit 0 if model id is listed for tool in catalog.
flowai_models_catalog_contains() {
  local tool="$1"
  local model="$2"
  local f
  f="$(flowai_models_catalog_path)"
  [[ -f "$f" ]] || return 1
  [[ -n "$model" ]] || return 1
  jq -e --arg t "$tool" --arg m "$model" \
    '.tools[$t].models | map(.id) | index($m) != null' "$f" >/dev/null 2>&1
}
