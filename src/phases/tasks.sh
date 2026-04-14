#!/usr/bin/env bash
# FlowAI — Tasks phase
#
# Produces tasks.md from spec + plan, then waits for Master Agent approval
# via one-shot AI review. If Master rejects, reads the rejection context,
# re-runs the AI with revision instructions, and re-emits tasks_produced.
# Loops until Master approves.
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/ai.sh"
source "$FLOWAI_HOME/src/core/phase.sh"

# Wait-UI rank for Master verdict polling (between pipeline Tasks and Implement; matches wait_ui scale).
readonly FLOWAI_WAIT_UI_RANK_TASKS_MASTER=22

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

readonly TASKS_REJECTION_FILE="${FLOWAI_DIR}/signals/tasks.rejection_context"
readonly TASKS_APPROVED_FILE="${FLOWAI_DIR}/signals/tasks.master_approved.ready"

_tasks_interrupt_handler() {
  printf '\n'
  log_warn "Tasks phase interrupted — pipeline may be stuck without tasks.ready."
  log_info "After fixing tasks.md, unblock with:  touch ${FLOWAI_DIR}/signals/tasks.master_approved.ready"
  log_info "Or re-run:  flowai run tasks"
  flowai_event_emit "tasks" "phase_aborted" "Tasks interrupted without Master approval"
  exit 130
}
trap '_tasks_interrupt_handler' INT TERM

_tasks_build_directive() {
  local revision_context="${1:-}"

  # If tasks.md already exists, tell the agent to read and improve it.
  local existing_hint=""
  if [[ -f "$FEATURE_DIR/tasks.md" ]] && [[ -s "$FEATURE_DIR/tasks.md" ]]; then
    existing_hint="
EXISTING ARTIFACT — a tasks.md already exists at the path above.
READ it first. Improve, refine, or complete it — do NOT start from scratch.
Only rewrite sections that conflict with the spec/plan or are incomplete."
  fi

  local directive="IMPORTANT PIPELINE DIRECTIVE:
You are assigned to Phase: Tasks (Implementation Breakdown).
Your WORKING DIRECTORY is: $PWD

CONTEXT — read the following upstream artifacts before starting:
  $FEATURE_DIR/spec.md
  $FEATURE_DIR/plan.md

OUTPUT FILE — you MUST write your artifact to this exact path:
  $FEATURE_DIR/tasks.md
${existing_hint}
Complete your phase tasks as thoroughly as possible. When you finish, exit immediately."

  if [[ -n "$revision_context" ]]; then
    directive="${directive}

--- [MASTER REVISION REQUEST] ---
The Master Agent reviewed your tasks.md and found issues. Focus on fixing them:

${revision_context}
---"
  fi

  printf '%s' "$directive"
}

# ─── Produce → Signal → Wait → (Retry) Loop ──────────────────────────────────

_tasks_iteration=0

while true; do
  _tasks_iteration=$((_tasks_iteration + 1))

  # On retry, inject Master's feedback (read + remove before building directive).
  local_revision=""
  if [[ "$_tasks_iteration" -gt 1 ]] && [[ -f "$TASKS_REJECTION_FILE" ]]; then
    local_revision="$(cat "$TASKS_REJECTION_FILE" 2>/dev/null || true)"
    rm -f "$TASKS_REJECTION_FILE" 2>/dev/null || true
    rm -f "${FLOWAI_DIR}/signals/tasks.verdict_complete" 2>/dev/null || true
  fi

  DIRECTIVE="$(_tasks_build_directive "$local_revision")"
  INJECTED_PROMPT="$(flowai_phase_write_prompt "tasks" "$ROLE_FILE" "$DIRECTIVE")"
  export INJECTED_PROMPT

  if [[ "$_tasks_iteration" -eq 1 ]]; then
    log_info "Booting Tasks phase..."
    flowai_event_emit "tasks" "started" "Beginning AI run"
  else
    log_info "Tasks phase — revision #$((_tasks_iteration - 1))..."
    flowai_event_emit "tasks" "revision" "Re-running AI with Master feedback"
  fi

  # Run AI to produce tasks.md
  flowai_ai_run "tasks" "$INJECTED_PROMPT" "false"

  # Verify the artifact was created
  if [[ -f "$FEATURE_DIR/tasks.md" ]] && [[ -s "$FEATURE_DIR/tasks.md" ]]; then
    # Drop stale tasks.ready from a previous pipeline/feature so Master does not skip
    # tasks_produced handling and Implement does not see a false "approved" signal.
    rm -f "${SIGNALS_DIR}/tasks.ready" 2>/dev/null || true
    flowai_event_emit "tasks" "tasks_produced" "tasks.md ready for Master review"
    log_info "tasks.md produced. Waiting for Master Agent review..."
  else
    log_error "tasks.md was not created by the AI agent."
    flowai_phase_emit_error "tasks" "tasks.md not produced"
    exit 1
  fi

  # ── Poll: wait for Master's single-round binding VERDICT ──
  _tasks_poll_elapsed=0
  while true; do
    if [[ -f "$TASKS_APPROVED_FILE" ]]; then
      flowai_wait_ui_clear_line
      flowai_wait_ui_release_if_owner "$FLOWAI_WAIT_UI_RANK_TASKS_MASTER"
      touch "$SIGNALS_DIR/tasks.ready"
      flowai_event_emit "tasks" "phase_complete" "Tasks approved by Master — advancing to Implement"
      log_success "Tasks approved. Handing off to Implementation phase."
      flowai_phase_schedule_close_phase_ui "tasks"
      exit 0
    fi

    if [[ -f "$TASKS_REJECTION_FILE" ]]; then
      flowai_wait_ui_clear_line
      flowai_wait_ui_release_if_owner "$FLOWAI_WAIT_UI_RANK_TASKS_MASTER"
      log_warn "Master rejected tasks — revising..."
      break
    fi

    sleep 3
    _tasks_poll_elapsed=$(( _tasks_poll_elapsed + 3 ))
    if flowai_wait_ui_claim_or_skip "$FLOWAI_WAIT_UI_RANK_TASKS_MASTER"; then
      flowai_wait_ui_pulse_line "$_tasks_poll_elapsed" 3 "Master review"
    fi
  done
done
