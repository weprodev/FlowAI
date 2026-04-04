#!/usr/bin/env bash
# Phase engine helpers — signals, feature dir resolution, approval gates.
# shellcheck shell=bash

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/config.sh"

export FLOWAI_DIR="${FLOWAI_DIR:-$PWD/.flowai}"
export SIGNALS_DIR="${FLOWAI_DIR}/signals"
export SPECS_DIR="${PWD}/specs"

if [[ ! -d "$FLOWAI_DIR" ]] || [[ ! -f "$FLOWAI_DIR/config.json" ]]; then
  log_error "Not a FlowAI project here — run: flowai init"
  exit 1
fi

flowai_phase_wait_for() {
  local signal="$1"
  local my_phase="$2"

  if [[ ! -f "$SIGNALS_DIR/${signal}.ready" ]]; then
    printf "\n${YELLOW}⏳ [%s] Waiting for upstream phase '%s' (.ready)...${RESET}\n" "$my_phase" "$signal"
    while [[ ! -f "$SIGNALS_DIR/${signal}.ready" ]]; do
      sleep 2
    done
    printf "${GREEN}✓ Upstream '%s' finished. Starting %s.${RESET}\n" "$signal" "$my_phase"
  fi
}

flowai_phase_resolve_feature_dir() {
  [[ -d "$SPECS_DIR" ]] || return 0
  find "$SPECS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r | head -n 1
}

# Returns 0 on approve, 1 retry agent / missing file loop, 2 needs-changes (reject path).
flowai_phase_verify_artifact() {
  local target_file="$1"
  local phase_name="$2"
  local current_signal="$3"

  while [[ ! -f "$target_file" ]]; do
    log_error "Required output file not found: $target_file"

    local action=""
    if command -v gum >/dev/null 2>&1; then
      action="$(gum choose 'Wait (I saved it)' 'Retry Agent' 'Create empty')"
    else
      read -r -p "Not found. [w]ait / [r]etry / [e]mpty: " action < /dev/tty || true
    fi

    case "$action" in
      *Retry*)
        return 1
        ;;
      *empty*|*Empty*|e|E)
        mkdir -p "$(dirname "$target_file")"
        touch "$target_file"
        ;;
      *)
        sleep 2
        ;;
    esac
  done

  log_success "$phase_name artifact present: $target_file"

  local decision=""
  if command -v gum >/dev/null 2>&1; then
    decision="$(gum choose 'Approve' 'Needs changes')"
  else
    read -r -p "Approve? [y/N]: " decision < /dev/tty || true
    [[ "$decision" =~ ^[yY] ]] && decision="Approve" || decision="Needs changes"
  fi

  if [[ "$decision" == "Approve" ]]; then
    touch "$SIGNALS_DIR/${current_signal}.ready"
    return 0
  fi

  touch "$SIGNALS_DIR/${current_signal}.reject" 2>/dev/null || true
  log_warn "Phase rejected — coordinate with Master, then resume."
  return 2
}

flowai_phase_resolve_role_prompt() {
  local phase="$1"

  if [[ -f "$FLOWAI_DIR/roles/${phase}.md" ]]; then
    printf '%s' "$FLOWAI_DIR/roles/${phase}.md"
    return
  fi

  local role_name=""
  case "$phase" in
    master|spec)
      role_name="master"
      ;;
    *)
      role_name="$(flowai_cfg_pipeline_role "$phase" "backend-engineer")"
      ;;
  esac

  if [[ -f "$FLOWAI_HOME/src/roles/${role_name}.md" ]]; then
    printf '%s' "$FLOWAI_HOME/src/roles/${role_name}.md"
  else
    printf '%s' "$FLOWAI_HOME/src/roles/backend-engineer.md"
  fi
}
