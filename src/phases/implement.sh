#!/usr/bin/env bash
# FlowAI — Implement phase
#
# Implements code based on spec + plan + tasks.
# After completion, emits 'impl_produced' and stays alive until Master
# signals approval or requests changes. This allows the Master Agent to
# review the implementation, ask for fixes, and get user sign-off before
# advancing to Review.
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/ai.sh"
source "$FLOWAI_HOME/src/core/phase.sh"

flowai_phase_wait_for "tasks" "Implement Phase"

FEATURE_DIR="$(flowai_phase_resolve_feature_dir)"
if [[ -z "$FEATURE_DIR" ]]; then
  log_error "No feature directory under specs/."
  exit 1
fi

if [[ "${FLOWAI_TEST_SKIP_AI:-}" == "1" ]]; then
  log_info "FLOWAI_TEST_SKIP_AI=1 — skipping AI run (contract test)."
  exit 0
fi

ROLE_FILE="$(flowai_phase_resolve_role_prompt "impl")"

# Check for rejection context from a previous review cycle
REJECTION_CONTEXT=""
REJECTION_CONTEXT_FILE="$FLOWAI_DIR/signals/impl.rejection_context"
if [[ -f "$REJECTION_CONTEXT_FILE" ]]; then
  REJECTION_CONTEXT="

--- [REVIEW REJECTION CONTEXT] ---
The Review phase REJECTED the previous implementation. Focus ONLY on these issues.
Do NOT re-implement tasks that already pass.

$(cat "$REJECTION_CONTEXT_FILE")
---"
  rm -f "$REJECTION_CONTEXT_FILE"
fi

DIRECTIVE="IMPORTANT PIPELINE DIRECTIVE:
You are assigned to Phase: Implement (Code Writing).
Your WORKING DIRECTORY is: $PWD

CONTEXT — read ALL upstream artifacts to understand the full picture:
  $FEATURE_DIR/spec.md    (original requirements and acceptance criteria)
  $FEATURE_DIR/plan.md    (architecture decisions and approach)
  $FEATURE_DIR/tasks.md   (implementation checklist — your primary input)

Implement the code required in tasks.md. Check off tasks as you complete them.
Verify your work against the acceptance criteria in spec.md.
Follow the architecture laid out in plan.md.
When blockers remain, document them and exit.${REJECTION_CONTEXT}"

INJECTED_PROMPT="$(flowai_phase_write_prompt "impl" "$ROLE_FILE" "$DIRECTIVE")"
export INJECTED_PROMPT

# ─── Progress Tracker ────────────────────────────────────────────────────────
_impl_track_progress() {
  local tasks_file="$1"
  local last_report=""
  while true; do
    sleep 10
    [[ -f "$tasks_file" ]] || continue
    local total done_count
    total="$(grep -cE '^[[:space:]]*- \[' "$tasks_file" 2>/dev/null || echo 0)"
    done_count="$(grep -cE '^[[:space:]]*- \[x\]' "$tasks_file" 2>/dev/null || echo 0)"
    local report="${done_count}/${total} tasks complete"
    if [[ "$report" != "$last_report" && "$total" -gt 0 ]]; then
      flowai_event_emit "impl" "progress" "$report"
      last_report="$report"
    fi
  done
}

log_info "Booting Implement phase..."

_impl_track_progress "$FEATURE_DIR/tasks.md" &
_PROGRESS_PID=$!
trap 'kill $_PROGRESS_PID 2>/dev/null || true' EXIT

# Run AI implementation
flowai_event_emit "impl" "started" "Beginning AI run"
flowai_ai_run "impl" "$INJECTED_PROMPT" "false"

# Signal completion to Master
flowai_event_emit "impl" "impl_produced" "Implementation complete — waiting for Master review"
log_info "Implementation complete. Waiting for Master Agent review..."

# ─── Stay Alive: Wait for Master instructions or approval ───────────────────
# Master will either:
#   1. Write impl.ready → we exit cleanly
#   2. Write impl.revision_context → we re-run with changes
while true; do
  if [[ -f "${FLOWAI_DIR}/signals/impl.ready" ]]; then
    log_success "Implementation approved by Master + User. Phase complete."
    flowai_event_emit "impl" "phase_complete" "Approved and signalled"
    break
  fi

  # Check for revision request from Master
  if [[ -f "$REJECTION_CONTEXT_FILE" ]]; then
    log_warn "Master requested changes. Re-running implementation..."
    flowai_event_emit "impl" "revision_requested" "Master requested changes"
    REJECTION_CONTEXT="

--- [MASTER REVISION REQUEST] ---
$(cat "$REJECTION_CONTEXT_FILE")
---"
    rm -f "$REJECTION_CONTEXT_FILE"

    # Rebuild directive with revision context
    DIRECTIVE_REV="${DIRECTIVE}${REJECTION_CONTEXT}"
    INJECTED_PROMPT="$(flowai_phase_write_prompt "impl" "$ROLE_FILE" "$DIRECTIVE_REV")"
    flowai_ai_run "impl" "$INJECTED_PROMPT" "false"
    flowai_event_emit "impl" "impl_produced" "Revised implementation — waiting for Master review"
    log_info "Revised implementation complete. Waiting for Master review..."
  fi

  sleep 3
done
