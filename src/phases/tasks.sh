#!/usr/bin/env bash
# FlowAI — Tasks phase
#
# Produces tasks.md from spec + plan, then waits for Master Agent approval
# (not human approval — Master auto-approves based on spec/plan alignment).
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/ai.sh"
source "$FLOWAI_HOME/src/core/phase.sh"

flowai_phase_wait_for "plan" "Tasks Phase"

FEATURE_DIR="$(flowai_phase_resolve_feature_dir)"
if [[ -z "$FEATURE_DIR" ]]; then
  log_error "No feature directory under specs/."
  exit 1
fi

if [[ "${FLOWAI_TEST_SKIP_AI:-}" == "1" ]]; then
  log_info "FLOWAI_TEST_SKIP_AI=1 — skipping AI run (contract test)."
  exit 0
fi

ROLE_FILE="$(flowai_phase_resolve_role_prompt "tasks")"
DIRECTIVE="IMPORTANT PIPELINE DIRECTIVE:
You are assigned to Phase: Tasks (Implementation Breakdown).
Your WORKING DIRECTORY is: $PWD

CONTEXT — read the following upstream artifacts before starting:
  $FEATURE_DIR/spec.md
  $FEATURE_DIR/plan.md

OUTPUT FILE — you MUST write your artifact to this exact path:
  $FEATURE_DIR/tasks.md

Complete your phase tasks as thoroughly as possible. When you finish, exit immediately."

INJECTED_PROMPT="$(flowai_phase_write_prompt "tasks" "$ROLE_FILE" "$DIRECTIVE")"
export INJECTED_PROMPT

log_info "Booting Tasks phase..."
flowai_event_emit "tasks" "started" "Beginning AI run"

# Run AI to produce tasks.md
flowai_ai_run "tasks" "$INJECTED_PROMPT" "false"

# Verify the artifact was created
if [[ -f "$FEATURE_DIR/tasks.md" ]] && [[ -s "$FEATURE_DIR/tasks.md" ]]; then
  flowai_event_emit "tasks" "tasks_produced" "tasks.md ready for Master review"
  log_info "tasks.md produced. Waiting for Master Agent approval..."
else
  log_error "tasks.md was not created by the AI agent."
  flowai_event_emit "tasks" "error" "tasks.md not produced"
  exit 1
fi

# Wait for Master approval (Master writes tasks.master_approved)
flowai_phase_wait_for "tasks.master_approved" "Tasks approval from Master"

# Master approved — emit the canonical tasks.ready signal for downstream
touch "$SIGNALS_DIR/tasks.ready"
flowai_event_emit "tasks" "phase_complete" "Tasks approved by Master — advancing to Implement"
log_success "Tasks approved. Handing off to Implementation phase."
