#!/usr/bin/env bash
# Validate model fields in .flowai/config.json against models-catalog.json
# shellcheck shell=bash

# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"
# shellcheck source=src/core/models-catalog.sh
[[ -n "${FLOWAI_HOME:-}" ]] && source "$FLOWAI_HOME/src/core/models-catalog.sh"

# Check one (tool, model) pair. Returns 0 if ok or empty; 1 if invalid (strict).
flowai_config_check_model_pair() {
  local label="$1" tool="${2//$'\r'/}" model="${3//$'\r'/}"
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
  flowai_config_hint_model_wrong_tool "$tool" "$model" "$label"
  return 1
}

# If this id exists under a different tool in the catalog, explain (e.g. gpt-4o under cursor vs gemini).
flowai_config_hint_model_wrong_tool() {
  local expect_tool="$1" model="$2" label="$3"
  local tline hint_tools=()

  while IFS= read -r tline; do
    [[ -z "$tline" ]] && continue
    if [[ "$tline" != "$expect_tool" ]]; then
      hint_tools+=("$tline")
    fi
  done < <(flowai_models_catalog_tools_listing_model "$model")

  ((${#hint_tools[@]})) || return 0

  local joined="" sep=""
  for tline in "${hint_tools[@]}"; do
    joined+="${sep}${tline}"
    sep=", "
  done

  local msg
  msg="Hint: '$model' is listed for tool(s): $joined — not for '$expect_tool'."
  if [[ "$label" == *"default_model"* ]]; then
    msg+=" Field default_model is only for the Gemini CLI; use a gemini id from flowai models list gemini (or move Cursor/OpenAI ids to master/roles with tool cursor)."
  elif [[ "$label" == "master" ]]; then
    msg+=" Set .master.tool to one of [$joined] if you meant that CLI, or choose a model id from flowai models list $expect_tool."
  else
    msg+=" Set roles.<role>.tool to match the vendor CLI, or pick an id from flowai models list $expect_tool."
  fi
  log_warn "$msg"
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

  # Normalize CRLF → LF on Windows (Git Bash / MSYS write CRLF).
  # jq parses JSON fine but -r output inherits the OS text mode, so
  # extracted values like "claude" become "claude\r" which breaks lookups.
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*)
      local _norm
      _norm="$(tr -d '\r' < "$cfg")" && printf '%s\n' "$_norm" > "$cfg" 2>/dev/null || true
      ;;
  esac

  if [[ ! -f "$(flowai_models_catalog_path)" ]]; then
    log_error "Model catalog not found: $(flowai_models_catalog_path)"
    return 1
  fi

  local dm cm mt mm rkey rtool rmodel
  dm="$(jq -r '.default_model // empty' "$cfg" | tr -d '\r')"
  cm="$(jq -r '.claude_default_model // empty' "$cfg" | tr -d '\r')"
  mt="$(jq -r '.master.tool // empty' "$cfg" | tr -d '\r')"
  mm="$(jq -r '.master.model // empty' "$cfg" | tr -d '\r')"

  flowai_config_check_model_pair "default_model (tool=gemini)" "gemini" "$dm" || err=1
  flowai_config_check_model_pair "claude_default_model (tool=claude)" "claude" "$cm" || err=1
  flowai_config_check_model_pair "master" "$mt" "$mm" || err=1

  while IFS=$'\t' read -r rkey rtool rmodel; do
    [[ -z "$rkey" ]] && continue
    flowai_config_check_model_pair "roles.${rkey}" "$rtool" "$rmodel" || err=1
  done < <(jq -r '.roles // {} | to_entries[] | [.key, (.value.tool // ""), (.value.model // "")] | @tsv' "$cfg" | tr -d '\r')

  [[ "$err" -eq 0 ]] && return 0
  return 1
}
