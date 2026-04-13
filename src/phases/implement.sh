#!/usr/bin/env bash
# FlowAI — Implement phase
#
# Implements code based on spec + plan + tasks.
# After completion, emits 'impl_produced', touches impl.code_complete.ready
# (unblocks Review / QA), and stays alive until Master final sign-off
# (impl.ready). Master or Review may request changes via impl.rejection_context.
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

# Signal completion — QA (Review) runs next; Master final sign-off is last
flowai_event_emit "impl" "impl_produced" "Implementation complete — QA (Review) next, then Master final sign-off"
touch "${FLOWAI_DIR}/signals/impl.code_complete.ready"
log_info "Implementation complete. Next: Review (QA) — Master final sign-off only after QA."
flowai_phase_focus "review" 2>/dev/null || true

# ─── Stay Alive: wait for Master final approval (after QA) or revision ────
# Master will either:
#   1. Write impl.ready (after QA + Master final sign-off) → exit cleanly
#   2. Write impl.rejection_context → re-run with changes
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

    # Merge via temp file so arbitrary rejection text cannot break quoting (set -euo pipefail).
    _impl_dir_merge="$(mktemp "${TMPDIR:-/tmp}/flowai_impl_directive_merge_XXXXXX")"
    {
      printf '%s\n' "$DIRECTIVE"
      printf '\n--- [MASTER REVISION REQUEST] ---\n'
      cat "$REJECTION_CONTEXT_FILE"
      printf '\n---\n'
    } > "$_impl_dir_merge"
    rm -f "$REJECTION_CONTEXT_FILE"

    INJECTED_PROMPT="$(flowai_phase_write_prompt "impl" "$ROLE_FILE" "$(cat "$_impl_dir_merge")")"
    rm -f "$_impl_dir_merge"
    flowai_ai_run "impl" "$INJECTED_PROMPT" "false"
    flowai_event_emit "impl" "impl_produced" "Revised implementation — QA (Review) next, then Master final sign-off"
    touch "${FLOWAI_DIR}/signals/impl.code_complete.ready"
    log_info "Revised implementation complete. Next: Review (QA) — Master final sign-off only after QA."
    flowai_phase_focus "review" 2>/dev/null || true
  fi

  sleep 3
done
