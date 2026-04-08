#!/usr/bin/env bash
# List valid model ids dynamically from the bundled catalog via tool plugins.
# Usage: flowai models [list] [<tool>|all]
# shellcheck shell=bash

set -euo pipefail

# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"
# shellcheck source=src/core/models-catalog.sh
source "$FLOWAI_HOME/src/core/models-catalog.sh"

_flowai_print_tool_block() {
  local tool="$1"
  local f
  f="$(flowai_models_catalog_path)"
  if [[ ! -f "$f" ]]; then return; fi

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

declare -a available_tools=()
if [[ -d "$FLOWAI_HOME/src/tools" ]]; then
  for tool_file in "$FLOWAI_HOME/src/tools/"*.sh; do
    [[ -f "$tool_file" ]] || continue
    # shellcheck disable=SC1090
    source "$tool_file"
    tool_name="$(basename "$tool_file" .sh)"
    available_tools+=("$tool_name")
  done
fi

_cmd_list() {
  local which="${1:-all}"
  
  if [[ "$which" == "all" ]]; then
    for t in "${available_tools[@]}"; do
      if type "flowai_tool_${t}_print_models" >/dev/null 2>&1; then
        "flowai_tool_${t}_print_models"
      fi
    done
    log_info "Configure in .flowai/config.json: default_model / claude_default_model / roles.*.model"
    log_info "Override validation: FLOWAI_ALLOW_UNKNOWN_MODEL=1"
    return 0
  fi
  
  if type "flowai_tool_${which}_print_models" >/dev/null 2>&1; then
    "flowai_tool_${which}_print_models"
  else
    local all_joined
    all_joined="$(IFS='|'; echo "${available_tools[*]}")"
    log_error "Unknown scope: $which (use: $all_joined|all)"
    exit 1
  fi
}

_models_main() {
  local scope="all"

  for a in "$@"; do
    if [[ "$a" == "list" ]]; then
      continue
    fi

    if [[ "$a" == "all" ]] || type "flowai_tool_${a}_print_models" >/dev/null 2>&1; then
      scope="$a"
      continue
    fi

    if [[ "$a" == "-h" || "$a" == "--help" || "$a" == "help" ]]; then
      local help_joined
      help_joined="$(IFS='|'; echo "${available_tools[*]}")"
      printf '%s\n' "Usage: flowai models [list] [$help_joined|all]"
      exit 0
    fi

    local err_joined
    err_joined="$(IFS='|'; echo "${available_tools[*]}")"
    log_error "Unknown argument: $a"
    printf '%s\n' "Usage: flowai models [list] [$err_joined|all]"
    exit 1
  done

  _cmd_list "$scope"
}

_models_main "$@"
