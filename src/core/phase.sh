#!/usr/bin/env bash
# Phase engine — signal coordination, feature dir resolution, human approval gates.
# shellcheck shell=bash

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/config.sh"
source "$FLOWAI_HOME/src/core/eventlog.sh"

export FLOWAI_DIR="${FLOWAI_DIR:-$PWD/.flowai}"
export SIGNALS_DIR="${FLOWAI_DIR}/signals"
export SPECS_DIR="${PWD}/specs"

if [[ ! -d "$FLOWAI_DIR" ]] || [[ ! -f "$FLOWAI_DIR/config.json" ]]; then
  log_error "Not a FlowAI project here — run: flowai init"
  exit 1
fi

# Block until <signal>.ready exists. Respects SIGINT (exit 130) and
# FLOWAI_PHASE_TIMEOUT_SEC (0 = unlimited, the default).
flowai_phase_wait_for() {
  local signal="$1"
  local my_phase="$2"

  [[ -f "$SIGNALS_DIR/${signal}.ready" ]] && return 0

  flowai_event_emit "$my_phase" "waiting" "Blocked on ${signal}.ready"
  printf "\n${YELLOW}⏳ [%s] Waiting for '%s'...${RESET}\n" "$my_phase" "$signal"

  local _interrupted=0
  trap '_interrupted=1' INT TERM

  local _elapsed=0
  local _timeout="${FLOWAI_PHASE_TIMEOUT_SEC:-0}"
  while [[ ! -f "$SIGNALS_DIR/${signal}.ready" ]]; do
    if [[ "$_interrupted" -eq 1 ]]; then
      trap - INT TERM
      log_warn "Wait interrupted — exiting ${my_phase}."
      exit 130
    fi
    if [[ "$_timeout" -gt 0 && "$_elapsed" -ge "$_timeout" ]]; then
      trap - INT TERM
      log_error "Timed out after ${_timeout}s waiting for '${signal}.ready' (${my_phase})."
      log_error "Set FLOWAI_PHASE_TIMEOUT_SEC=0 to wait indefinitely."
      exit 1
    fi
    sleep 2
    _elapsed=$(( _elapsed + 2 ))
  done

  trap - INT TERM
  printf "${GREEN}✓ '%s' ready — starting %s.${RESET}\n" "$signal" "$my_phase"
}

# Return the most recently created feature directory under specs/, or empty.
# In test mode (FLOWAI_TESTING=1) auto-picks the latest; otherwise prompts
# when multiple directories exist.
flowai_phase_resolve_feature_dir() {
  [[ -d "$SPECS_DIR" ]] || return 0

  local -a dirs=()
  while IFS= read -r d; do
    [[ -n "$d" ]] && dirs+=("$d")
  done < <(find "$SPECS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r)

  case "${#dirs[@]}" in
    0) return 0 ;;
    1) printf '%s' "${dirs[0]}" ;;
    *)
      if [[ "${FLOWAI_TESTING:-0}" == "1" ]]; then
        printf '%s' "${dirs[0]}"
      elif command -v gum >/dev/null 2>&1; then
        gum choose "${dirs[@]}"
      else
        local i=1
        printf '\nMultiple feature directories found:\n' >/dev/tty
        for d in "${dirs[@]}"; do
          printf '  %d) %s\n' "$i" "$(basename "$d")" >/dev/tty
          i=$(( i + 1 ))
        done
        local ans=""
        read -r -p "Select (1-${#dirs[@]}) [1]: " ans </dev/tty || true
        if [[ "$ans" =~ ^[0-9]+$ ]] && [[ "$ans" -ge 1 ]] && [[ "$ans" -le "${#dirs[@]}" ]]; then
          printf '%s' "${dirs[$(( ans - 1 ))]}"
        else
          printf '%s' "${dirs[0]}"
        fi
      fi
      ;;
  esac
}

# Prompt the human to approve a phase artifact.
# Returns: 0 = approved, 1 = retry agent, 2 = needs changes (reject).
flowai_phase_verify_artifact() {
  local target_file="$1"
  local phase_name="$2"
  local current_signal="$3"

  while [[ ! -f "$target_file" ]]; do
    log_error "Required output not found: $target_file"

    local action=""
    if command -v gum >/dev/null 2>&1; then
      action="$(gum choose 'Wait (I saved it)' 'Retry Agent' 'Create empty')"
    else
      read -r -p "Not found. [w]ait / [r]etry / [e]mpty: " action < /dev/tty || true
    fi

    case "$action" in
      *Retry*) return 1 ;;
      *empty*|*Empty*|e|E)
        mkdir -p "$(dirname "$target_file")"
        touch "$target_file"
        ;;
      *) sleep 2 ;;
    esac
  done

  flowai_event_emit "$phase_name" "artifact_produced" "$target_file"
  log_success "$phase_name artifact ready: $target_file"

  while true; do
    local decision=""
    if command -v gum >/dev/null 2>&1; then
      decision="$(gum choose 'Approve' 'Needs changes' 'Review artifact')"
    else
      read -r -p "Approve / Needs changes / Review? [a/n/r]: " decision < /dev/tty || true
      case "$decision" in
        a*|A*) decision="Approve" ;;
        r*|R*) decision="Review artifact" ;;
        *)     decision="Needs changes" ;;
      esac
    fi

    if [[ "$decision" == "Review artifact" ]]; then
      local my_editor="${EDITOR:-cursor}"
      if command -v gum >/dev/null 2>&1; then
        local mode
        mode="$(gum choose 'Read here (Terminal)' 'Open in Editor')"
        if [[ "$mode" == "Open in Editor" ]]; then
          command -v "$my_editor" >/dev/null 2>&1 || my_editor="vi"
          "$my_editor" "$target_file" </dev/tty >/dev/tty 2>&1 || true
        else
          gum pager < "$target_file"
        fi
      else
        read -r -p "Read in [t]erminal or [e]ditor?: " mode < /dev/tty || true
        if [[ "$mode" =~ ^[eE] ]]; then
          command -v "$my_editor" >/dev/null 2>&1 || my_editor="vi"
          log_info "Opening in $my_editor..."
          "$my_editor" "$target_file" </dev/tty >/dev/tty 2>&1 || true
        else
          less -R "$target_file" </dev/tty >/dev/tty 2>&1 || cat "$target_file"
        fi
      fi
      printf "\n"
      continue
    fi

    if [[ "$decision" == "Approve" ]]; then
      touch "$SIGNALS_DIR/${current_signal}.ready"
      flowai_event_emit "$phase_name" "approved" "$target_file"
      return 0
    fi

    touch "$SIGNALS_DIR/${current_signal}.reject" 2>/dev/null || true
    flowai_event_emit "$phase_name" "rejected" "Human rejected artifact"
    log_warn "Phase rejected — coordinate with Master, then resume."
    return 2
  done
}

# Compose the injected prompt file: role content + phase directive.
# Prints the path of the written file.
# Usage: flowai_phase_write_prompt <phase_name> <role_file> <directive>
flowai_phase_write_prompt() {
  local phase_name="$1"
  local role_file="$2"
  local directive="$3"
  local out="${FLOWAI_DIR}/launch/${phase_name}_prompt.md"
  mkdir -p "${FLOWAI_DIR}/launch"
  { cat "$role_file"; printf '\n%s\n' "$directive"; } > "$out"
  printf '%s' "$out"
}

# Run the AI → approve loop for a phase.
# Usage: flowai_phase_run_loop <phase_name> <prompt_file> <artifact_file> <label> <signal>
flowai_phase_run_loop() {
  local phase_name="$1"
  local prompt_file="$2"
  local artifact_file="$3"
  local artifact_label="$4"
  local signal_name="$5"

  flowai_event_emit "$phase_name" "started" "Beginning AI run"

  while true; do
    flowai_ai_run "$phase_name" "$prompt_file" "false"
    flowai_phase_verify_artifact "$artifact_file" "$artifact_label" "$signal_name"
    local rc=$?
    if [[ "$rc" -eq 0 ]]; then
      flowai_event_emit "$phase_name" "phase_complete" "Approved and signalled"
      break
    fi
    if [[ "$rc" -eq 2 ]]; then
      rm -f "$SIGNALS_DIR/${signal_name}.reject" 2>/dev/null || true
      flowai_phase_wait_for "${signal_name}.revision" "${artifact_label} revision"
      rm -f "$SIGNALS_DIR/${signal_name}.revision.ready" 2>/dev/null || true
    fi
  done
}

# Resolve the role prompt file for a phase.
#
# Resolution chain (first match wins):
#   Tier 1  .flowai/roles/<phase>.md          — phase-level file drop (undocumented today, now documented)
#   Tier 2  .flowai/roles/<role-name>.md      — role-level file drop (NEW)
#   Tier 3  config.json roles[<role>].prompt_file — project-relative path in repo (NEW)
#   Tier 4  $FLOWAI_HOME/src/roles/<role>.md  — bundled
#   Tier 5  $FLOWAI_HOME/src/roles/backend-engineer.md — ultimate fallback
flowai_phase_resolve_role_prompt() {
  local phase="$1"

  # Resolve the role name for this phase
  local role_name=""
  case "$phase" in
    master|spec) role_name="master" ;;
    *)           role_name="$(flowai_cfg_pipeline_role "$phase" "backend-engineer")" ;;
  esac

  # Tier 1 — phase-level override (e.g. .flowai/roles/plan.md)
  if [[ -f "$FLOWAI_DIR/roles/${phase}.md" ]]; then
    printf '%s' "$FLOWAI_DIR/roles/${phase}.md"
    return
  fi

  # Tier 2 — role-name override (e.g. .flowai/roles/team-lead.md)
  if [[ -f "$FLOWAI_DIR/roles/${role_name}.md" ]]; then
    printf '%s' "$FLOWAI_DIR/roles/${role_name}.md"
    return
  fi

  # Tier 3 — config.json prompt_file (project-relative, version-controlled)
  if [[ -f "$FLOWAI_DIR/config.json" ]]; then
    local prompt_file
    prompt_file="$(jq -r --arg r "$role_name" '.roles[$r].prompt_file // empty' "$FLOWAI_DIR/config.json" 2>/dev/null)"
    if [[ -n "$prompt_file" ]] && flowai_validate_repo_rel_path "$prompt_file" && [[ -f "$PWD/$prompt_file" ]]; then
      printf '%s' "$PWD/$prompt_file"
      return
    fi
  fi

  # Tier 4 — bundled role file
  if [[ -f "$FLOWAI_HOME/src/roles/${role_name}.md" ]]; then
    printf '%s' "$FLOWAI_HOME/src/roles/${role_name}.md"
    return
  fi

  # Tier 5 — ultimate fallback
  printf '%s' "$FLOWAI_HOME/src/roles/backend-engineer.md"
}

