#!/usr/bin/env bash
# List valid model ids from the bundled catalog (per vendor CLI).
# Usage: flowai models [list] [claude|gemini|cursor|all]
# shellcheck shell=bash

set -euo pipefail

# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"
# shellcheck source=src/core/models-catalog.sh
source "$FLOWAI_HOME/src/core/models-catalog.sh"

_cmd_list() {
  local which="${1:-all}"
  local f
  f="$(flowai_models_catalog_path)"
  if [[ ! -f "$f" ]]; then
    log_error "Model catalog not found: $f"
    exit 1
  fi

  _print_tool_block() {
    local tool="$1"
    local doc
    doc="$(flowai_models_catalog_doc_for_tool "$tool")"
    log_header "Valid models: ${tool}"
    if [[ -n "$doc" ]]; then
      log_info "Docs: $doc"
    fi
    local models_doc
    models_doc="$(jq -r --arg t "$tool" '.tools[$t].models_doc // empty' "$f" 2>/dev/null)"
    if [[ -n "$models_doc" ]]; then
      log_info "Models index: $models_doc"
    fi
    local note
    note="$(jq -r --arg t "$tool" '.tools[$t].note // empty' "$f" 2>/dev/null)"
    if [[ -n "$note" ]]; then
      log_info "$note"
    fi
    printf '  default_id: %s\n\n' "$(flowai_models_catalog_default_for_tool "$tool")"
    jq -r --arg t "$tool" \
      '.tools[$t].models[] | "  \(.id)  (\(.kind // "-"))  \(.description // "")"' "$f"
    printf '\n'
  }

  case "$which" in
    claude)
      _print_tool_block claude
      ;;
    gemini)
      _print_tool_block gemini
      ;;
    cursor)
      _print_tool_block cursor
      ;;
    all)
      _print_tool_block gemini
      _print_tool_block claude
      _print_tool_block cursor
      log_info "Configure in .flowai/config.json: default_model / claude_default_model / roles.*.model"
      log_info "Override validation: FLOWAI_ALLOW_UNKNOWN_MODEL=1"
      ;;
    *)
      log_error "Unknown scope: $which (use: claude, gemini, cursor, all)"
      exit 1
      ;;
  esac
}

scope="all"
for a in "$@"; do
  case "$a" in
    list) ;;
    claude|gemini|cursor|all) scope="$a" ;;
    -h|--help|help)
      printf '%s\n' "Usage: flowai models [list] [claude|gemini|cursor|all]"
      exit 0
      ;;
    *)
      log_error "Unknown argument: $a"
      printf '%s\n' "Usage: flowai models [list] [claude|gemini|cursor|all]"
      exit 1
      ;;
  esac
done

_cmd_list "$scope"
