#!/usr/bin/env bash
# Validate model fields in .flowai/config.json against models-catalog.json
# shellcheck shell=bash

# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"
# shellcheck disable=SC1091
[[ -n "${FLOWAI_HOME:-}" ]] && source "$FLOWAI_HOME/src/core/models-catalog.sh"

# Check one (tool, model) pair. Returns 0 if ok or empty; 1 if invalid (strict).
flowai_config_check_model_pair() {
  local label="$1" tool="$2" model="$3"
  local loose=0
  [[ "${FLOWAI_ALLOW_UNKNOWN_MODEL:-0}" == "1" ]] && loose=1

  [[ -z "$model" || "$model" == "null" ]] && return 0
  [[ -z "$tool" || "$tool" == "null" ]] && return 0

  if ! flowai_models_catalog_has_tool "$tool"; then
    if [[ "$loose" -eq 1 ]]; then
      log_warn "Unknown tool '$tool' at $label — not in models-catalog.json"
      return 0
    fi
    log_error "Unknown tool '$tool' at $label — add it under \"tools\" in models-catalog.json or fix the typo."
    return 1
  fi

  if flowai_models_catalog_contains "$tool" "$model"; then
    return 0
  fi

  if [[ "$loose" -eq 1 ]]; then
    log_warn "Model '$model' at $label not listed for tool '$tool' (FLOWAI_ALLOW_UNKNOWN_MODEL=1)"
    return 0
  fi

  log_error "Invalid model '$model' at $label — not in models-catalog.json for tool '$tool'. Run: flowai models list $tool"
  return 1
}

# Validate default_model (gemini), claude_default_model (claude), master, and roles.*.
# Exit 0 if all ok or loose mode; 1 if any strict failure.
flowai_config_validate_models() {
  local cfg="${FLOWAI_CONFIG:-${FLOWAI_DIR:-}/config.json}"
  local err=0

  if [[ ! -f "$cfg" ]]; then
    log_error "Config not found: $cfg"
    return 1
  fi

  if [[ ! -f "$(flowai_models_catalog_path)" ]]; then
    log_error "Model catalog not found: $(flowai_models_catalog_path)"
    return 1
  fi

  local dm cm mt mm rkey rtool rmodel
  dm="$(jq -r '.default_model // empty' "$cfg")"
  cm="$(jq -r '.claude_default_model // empty' "$cfg")"
  mt="$(jq -r '.master.tool // empty' "$cfg")"
  mm="$(jq -r '.master.model // empty' "$cfg")"

  flowai_config_check_model_pair "default_model (tool=gemini)" "gemini" "$dm" || err=1
  flowai_config_check_model_pair "claude_default_model (tool=claude)" "claude" "$cm" || err=1
  flowai_config_check_model_pair "master" "$mt" "$mm" || err=1

  while IFS=$'\t' read -r rkey rtool rmodel; do
    [[ -z "$rkey" ]] && continue
    flowai_config_check_model_pair "roles.${rkey}" "$rtool" "$rmodel" || err=1
  done < <(jq -r '.roles // {} | to_entries[] | [.key, (.value.tool // ""), (.value.model // "")] | @tsv' "$cfg")

  [[ "$err" -eq 0 ]] && return 0
  return 1
}
