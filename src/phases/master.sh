#!/usr/bin/env bash
# FlowAI - Master Phase
#
# The Master Agent operates in two modes:
#   Phase 1: Interactive spec creation (existing behavior)
#   Phase 2: Pipeline monitoring — watches event log for progress, rejections,
#            and completion. Re-invokes AI on rejection for guidance.
#
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/ai.sh"
source "$FLOWAI_HOME/src/core/phase.sh"

ROLE_FILE=""
if [[ -f "$FLOWAI_DIR/roles/master.md" ]]; then
    ROLE_FILE="$FLOWAI_DIR/roles/master.md"
else
    ROLE_FILE="$FLOWAI_HOME/src/roles/master.md"
fi

log_info "Booting Master Agent..."
flowai_event_emit "master" "started" "Master agent interactive session"

# ─── Phase 1: Interactive Spec Creation ──────────────────────────────────────
# Master is interactive, does not wait for a previous phase

FEATURE_DIR="$(flowai_phase_resolve_feature_dir)"
if [[ -z "$FEATURE_DIR" ]]; then
  # Fallback if no specs directory exists yet or if flowai_phase_resolve_feature_dir failed
  current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
  if [[ -n "$current_branch" && "$current_branch" != "main" && "$current_branch" != "master" ]]; then
    FEATURE_DIR="$PWD/specs/$current_branch"
  else
    FEATURE_DIR="$PWD/specs/default"
  fi
  mkdir -p "$FEATURE_DIR"
fi

DIRECTIVE="IMPORTANT PIPELINE DIRECTIVE:
You are assigned to Phase: Specification (Master Agent).
Your task is to comprehensively define the specification for this feature.
Your WORKING DIRECTORY is: $PWD

OUTPUT FILE — you MUST write your specification artifact to this exact path:
  $FEATURE_DIR/spec.md

When you are finished generating spec.md, tell the user, and then remain available for feedback."

INJECTED_PROMPT="$(flowai_phase_write_prompt "master" "$ROLE_FILE" "$DIRECTIVE")"
export INJECTED_PROMPT

flowai_ai_run "master" "$INJECTED_PROMPT" "true"

flowai_event_emit "master" "phase_complete" "Spec creation complete"

# ─── Phase 2: Pipeline Monitoring ────────────────────────────────────────────
# After spec creation, monitor the pipeline for progress and rejections.
# This keeps the master pane alive and responsive to downstream events.

log_header "Master Agent — Pipeline Monitor"
log_info "Monitoring pipeline progress. The master will re-engage on rejections."
log_info "Press Ctrl+C to exit monitoring."

_master_last_processed_line=0
_master_interrupted=0
trap '_master_interrupted=1' INT TERM

_master_display_status() {
  local status
  status="$(flowai_event_pipeline_status)"
  if [[ -n "$status" && "$status" != "{}" ]]; then
    printf "\r${CYAN}Pipeline: %s${RESET}" \
      "$(printf '%s' "$status" | jq -r 'to_entries | map("\(.key)=\(.value)") | join(" · ")' 2>/dev/null || echo "$status")"
  fi
}

_master_check_for_rejections() {
  [[ -f "$FLOWAI_EVENTS_FILE" ]] || return 0

  local total_lines
  total_lines="$(wc -l < "$FLOWAI_EVENTS_FILE" | tr -d ' ')"

  # Check if log was truncated/reset
  if [[ "$total_lines" -lt "$_master_last_processed_line" ]]; then
    _master_last_processed_line=0
  fi

  # Only process new lines since last check
  if [[ "$total_lines" -le "$_master_last_processed_line" ]]; then
    return 0
  fi

  local new_events
  new_events="$(tail -n +"$((_master_last_processed_line + 1))" "$FLOWAI_EVENTS_FILE")"
  _master_last_processed_line="$total_lines"

  # Check for rejection events
  local rejection
  rejection="$(printf '%s' "$new_events" | grep '"event":"rejected"' | tail -1 || true)"
  if [[ -n "$rejection" ]]; then
    local rej_phase rej_detail
    rej_phase="$(printf '%s' "$rejection" | jq -r '.phase' 2>/dev/null)"
    rej_detail="$(printf '%s' "$rejection" | jq -r '.detail // "No details"' 2>/dev/null)"

    printf '\n'
    log_warn "REJECTION detected in phase: $rej_phase"
    log_warn "Detail: $rej_detail"
    log_info "Re-invoking Master Agent with rejection context..."

    # Build a context prompt with rejection info and recent events
    local context_prompt
    context_prompt="$(mktemp "${TMPDIR:-/tmp}/flowai_master_reenter_XXXXXX")"
    {
      cat "$ROLE_FILE"
      printf '\n\n--- [REJECTION CONTEXT] ---\n'
      printf 'The **%s** phase was REJECTED by the human reviewer.\n' "$rej_phase"
      printf 'Rejection detail: %s\n\n' "$rej_detail"
      printf 'Recent pipeline events:\n'
      flowai_event_format_for_prompt 20
      printf '\n\nYour task: Analyze why the rejection occurred. Review the artifacts '
      printf 'in the specs/ directory. Provide guidance on how to fix the issue, '
      printf 'or revise the spec if the original requirements were unclear.\n'
      printf 'When ready, signal the revision by explaining what you changed.\n---\n'
    } > "$context_prompt"

    flowai_event_emit "master" "re-engaged" "Responding to $rej_phase rejection"
    flowai_ai_run "master" "$context_prompt" "true"
    rm -f "$context_prompt"

    flowai_event_emit "master" "guidance_provided" "Master responded to $rej_phase rejection"
  fi

  # Check for pipeline completion
  local completion
  completion="$(printf '%s' "$new_events" | grep '"phase":"review"' | grep '"event":"phase_complete"' || true)"
  if [[ -n "$completion" ]]; then
    printf '\n'
    flowai_event_emit "master" "pipeline_complete" "All phases done"
    log_success "Pipeline complete! All phases approved."
    log_info "Review the final artifacts in specs/ and the implemented code."
    return 1  # Signal to exit the monitor loop
  fi

  return 0
}

while [[ "$_master_interrupted" -eq 0 ]]; do
  _master_display_status
  if ! _master_check_for_rejections; then
    break  # Pipeline complete
  fi
  sleep 5
done

trap - INT TERM

if [[ "$_master_interrupted" -eq 1 ]]; then
  printf '\n'
  log_info "Master monitoring stopped by user."
  flowai_event_emit "master" "monitoring_stopped" "User interrupted"
fi

log_info "Master Agent session ended."
