#!/usr/bin/env bash
# FlowAI - Master Phase
#
# The Master Agent is the central orchestrator of the entire pipeline.
#
#   Phase 1: Interactive spec creation — user directs the AI, approves spec
#            in conversation (AI writes approval marker), pipeline auto-advances.
#   Phase 2: Active pipeline orchestration — Master controls phase transitions,
#            reviews downstream artifacts, manages agent lifecycles, and is the
#            single point of contact for the user.
#
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/ai.sh"
source "$FLOWAI_HOME/src/core/phase.sh"
source "$FLOWAI_HOME/src/bootstrap/specify.sh"

# Role resolution — uses the same 5-tier chain as every other phase.
ROLE_FILE="$(flowai_phase_resolve_role_prompt "master")"

log_info "Booting Master Agent..."
flowai_event_emit "master" "started" "Master agent interactive session"

# ─── Phase 1: Interactive Spec Creation ──────────────────────────────────────

FEATURE_DIR="$(flowai_phase_resolve_feature_dir)"
if [[ -z "$FEATURE_DIR" ]]; then
  current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
  if [[ -n "$current_branch" && "$current_branch" != "main" && "$current_branch" != "master" ]]; then
    FEATURE_DIR="$PWD/specs/$current_branch"
  else
    FEATURE_DIR="$PWD/specs/default"
  fi
  mkdir -p "$FEATURE_DIR"
fi

SPEC_FILE="$FEATURE_DIR/spec.md"
APPROVAL_MARKER="${FLOWAI_DIR}/signals/spec.user_approved"

# Resolve constitution file for memory learning
MEMORY_FILE=""
if declare -F flowai_specify_constitution_path >/dev/null 2>&1; then
  MEMORY_FILE="$(flowai_specify_constitution_path "$PWD")"
fi
if [[ -z "$MEMORY_FILE" ]]; then
  MEMORY_FILE="$PWD/.specify/memory/constitution.md"
fi

DIRECTIVE="IMPORTANT PIPELINE DIRECTIVE:
You are assigned to Phase: Specification (Master Agent).
Your task is to comprehensively define the specification for this feature.
Your WORKING DIRECTORY is: $PWD

OUTPUT FILE — you MUST write your specification artifact to this exact path:
  $SPEC_FILE

APPROVAL PROTOCOL:
- After creating spec.md, tell the user the exact file path and ask them to review it.
- WAIT for the user to explicitly approve (e.g., 'approved', 'go ahead', 'looks good').
- Do NOT assume approval. The user must say it.
- When the user gives explicit approval, you MUST do two things:
  1. Confirm: 'Spec approved. I will hand it over to the Plan Agent and continue monitoring.'
  2. Create this marker file: $APPROVAL_MARKER
     Write the single word 'approved' to that file.
- If the user requests changes, revise spec.md and ask for approval again.
- Do NOT create the marker file until the user explicitly approves.

MEMORY LEARNING PROTOCOL:
When the user provides feedback (rejections, change requests, or any instructions),
analyze whether the feedback contains a REUSABLE BEHAVIORAL RULE — something that
should apply to ALL future features in this project, not just this task.

Examples of permanent rules:
  - 'Never skip creating tests' → project rule
  - 'Always use dependency injection' → project rule
  - 'Use PostgreSQL, not SQLite' → project rule
Examples of task-specific instructions (NOT rules):
  - 'Add more details about authentication' → this task only
  - 'Fix the typo on line 42' → this task only

If you detect a permanent rule:
  1. Ask the user: 'This seems like a rule we should follow in all future tasks.
     Should I add it to project memory so all agents follow this going forward?'
  2. If the user says YES:
     - Append the rule as a new bullet to: $MEMORY_FILE
       under the '## Core Principles' section.
       Format: 'N. **Short title** — description of the rule.'
     - Confirm: '✅ Added to project memory. All future agents will follow this.'
  3. If the user says NO:
     - Confirm: 'Got it — applying for this task only.'
     - Do NOT write anything to the memory file."


INJECTED_PROMPT="$(flowai_phase_write_prompt "master" "$ROLE_FILE" "$DIRECTIVE")"
export INJECTED_PROMPT

# ─── Background Approval Watcher ────────────────────────────────────────────
# Polls for BOTH spec.md AND the user approval marker. Only emits spec.ready
# when the user has explicitly approved through the AI conversation.
# This ensures the user MUST approve before the pipeline advances.
_master_approval_watcher() {
  local spec_file="$1"
  local approval_marker="$2"
  local signals_dir="${FLOWAI_DIR}/signals"

  while true; do
    if [[ -f "$signals_dir/spec.ready" ]]; then
      return 0  # Already signalled
    fi
    if [[ -f "$spec_file" ]] && [[ -s "$spec_file" ]] && [[ -f "$approval_marker" ]]; then
      # Both spec.md and approval marker exist — user approved
      touch "$signals_dir/spec.ready"
      flowai_event_emit "master" "artifact_produced" "$spec_file"
      flowai_event_emit "master" "approved" "spec.md approved by user"
      flowai_event_emit "master" "phase_complete" "Spec approved — pipeline advancing to Plan"
      log_success "Spec approved by user — pipeline advancing to Plan phase."
      # Switch focus to Plan pane
      flowai_phase_focus "plan" 2>/dev/null || true
      return 0
    fi
    sleep 3
  done
}

_master_approval_watcher "$SPEC_FILE" "$APPROVAL_MARKER" &
_watcher_pid=$!

flowai_ai_run "master" "$INJECTED_PROMPT" "true"

# ─── Post-Session Cleanup ───────────────────────────────────────────────────
kill "$_watcher_pid" 2>/dev/null || true
wait "$_watcher_pid" 2>/dev/null || true

# Fallback: if user exited REPL without the AI creating the marker,
# fall through to the manual gum/read approval gate
if [[ ! -f "${FLOWAI_DIR}/signals/spec.ready" ]]; then
  log_warn "Spec approval marker was not detected. Entering manual approval..."
  while true; do
    flowai_phase_verify_artifact "$SPEC_FILE" "Specification" "spec"
    _spec_rc=$?
    if [[ "$_spec_rc" -eq 0 ]]; then
      flowai_event_emit "master" "phase_complete" "Spec approved — pipeline advancing to Plan"
      flowai_phase_focus "plan" 2>/dev/null || true
      break
    fi
    if [[ "$_spec_rc" -eq 2 ]]; then
      flowai_event_emit "master" "rejected" "Human rejected spec — re-entering interactive session"
    fi
    log_warn "Re-entering interactive session for spec revision..."
    flowai_ai_run "master" "$INJECTED_PROMPT" "true"
  done
fi

# Clean up the approval marker for potential re-runs
rm -f "$APPROVAL_MARKER" 2>/dev/null || true

# ─── Phase 2: Active Pipeline Orchestration ─────────────────────────────────
# The Master is now the central brain. It actively monitors phase transitions,
# reviews downstream artifacts, auto-approves tasks, and mediates between
# the implementation agent and the user for final sign-off.

log_header "Master Agent — Pipeline Orchestrator"
log_info "Monitoring pipeline. I'll manage all phase transitions."
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

_master_check_events() {
  [[ -f "$FLOWAI_EVENTS_FILE" ]] || return 0

  local total_lines
  total_lines="$(wc -l < "$FLOWAI_EVENTS_FILE" | tr -d ' ')"

  if [[ "$total_lines" -lt "$_master_last_processed_line" ]]; then
    _master_last_processed_line=0
  fi
  if [[ "$total_lines" -le "$_master_last_processed_line" ]]; then
    return 0
  fi

  local new_events
  new_events="$(tail -n +"$((_master_last_processed_line + 1))" "$FLOWAI_EVENTS_FILE")"
  _master_last_processed_line="$total_lines"

  # ── Plan phase approved → switch focus to Tasks ──
  local plan_approved
  plan_approved="$(printf '%s' "$new_events" | grep '"phase":"plan"' | grep '"event":"phase_complete"' || true)"
  if [[ -n "$plan_approved" ]]; then
    printf '\n'
    log_success "Plan phase approved. Preparing Tasks phase..."
    flowai_phase_focus "tasks" 2>/dev/null || true
  fi

  # ── Tasks produced → Master AI auto-approves ──
  local tasks_ready
  tasks_ready="$(printf '%s' "$new_events" | grep '"phase":"tasks"' | grep '"event":"tasks_produced"' || true)"
  if [[ -n "$tasks_ready" ]] && [[ ! -f "${FLOWAI_DIR}/signals/tasks.ready" ]]; then
    printf '\n'
    log_info "Tasks breakdown produced. Master reviewing..."
    # Master auto-approves tasks (user approved spec+plan, Master validates alignment)
    if [[ -f "$FEATURE_DIR/tasks.md" ]] && [[ -s "$FEATURE_DIR/tasks.md" ]]; then
      touch "${FLOWAI_DIR}/signals/tasks.master_approved.ready"
      flowai_event_emit "master" "tasks_reviewed" "Master approved tasks breakdown"
      log_success "Tasks approved by Master. Starting implementation..."
      flowai_phase_focus "impl" 2>/dev/null || true
    else
      log_warn "tasks.md not found or empty — waiting for Tasks agent to produce it."
    fi
  fi

  # ── Implementation complete → Master reviews + asks user ──
  local impl_complete
  impl_complete="$(printf '%s' "$new_events" | grep '"phase":"impl"' | grep '"event":"impl_produced"' || true)"
  if [[ -n "$impl_complete" ]] && [[ ! -f "${FLOWAI_DIR}/signals/impl.ready" ]]; then
    printf '\n'
    log_header "Implementation Complete — Master Review"
    log_info "The implementation agent has finished. Reviewing changes..."

    # Master AI reviews the implementation
    local review_prompt
    review_prompt="$(mktemp "${TMPDIR:-/tmp}/flowai_master_review_XXXXXX")"
    {
      cat "$ROLE_FILE"
      printf '\n%s\n' "$DIRECTIVE"
      printf '\n\n--- [IMPLEMENTATION REVIEW] ---\n'
      printf 'The Implementation agent has completed all tasks.\n'
      printf 'Review the following artifacts:\n'
      printf '  spec.md:  %s\n' "$FEATURE_DIR/spec.md"
      printf '  plan.md:  %s\n' "$FEATURE_DIR/plan.md"
      printf '  tasks.md: %s\n' "$FEATURE_DIR/tasks.md"
      printf '\nReview the code changes (run git diff if needed).\n'
      printf 'If changes are needed, prepare a list of improvements.\n'
      printf 'When satisfied, ask the user to review and approve the implementation.\n'
      printf '\nAPPROVAL PROTOCOL:\n'
      printf 'When the user approves, create this file: %s\n' "${FLOWAI_DIR}/signals/impl.user_approved"
      printf 'Write the single word "approved" to it.\n---\n'
    } > "$review_prompt"

    flowai_event_emit "master" "reviewing_impl" "Master reviewing implementation"
    flowai_ai_run "master" "$review_prompt" "true"
    rm -f "$review_prompt"

    # Check if user approved through the REPL
    if [[ -f "${FLOWAI_DIR}/signals/impl.user_approved" ]]; then
      touch "${FLOWAI_DIR}/signals/impl.ready"
      flowai_event_emit "master" "impl_approved" "Implementation approved by user through Master"
      log_success "Implementation approved! Advancing to Review phase."
      rm -f "${FLOWAI_DIR}/signals/impl.user_approved" 2>/dev/null || true
      flowai_phase_focus "review" 2>/dev/null || true
    else
      # User exited without approving — use manual gate
      log_warn "No approval marker detected. Using manual approval gate..."
      flowai_phase_verify_artifact "$FEATURE_DIR/tasks.md" "Implementation" "impl"
      local impl_rc=$?
      if [[ "$impl_rc" -eq 0 ]]; then
        flowai_event_emit "master" "impl_approved" "Implementation approved manually"
        log_success "Implementation approved! Advancing to Review phase."
        flowai_phase_focus "review" 2>/dev/null || true
      fi
    fi
  fi

  # ── Rejection in any downstream phase ──
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

    local context_prompt
    context_prompt="$(mktemp "${TMPDIR:-/tmp}/flowai_master_reenter_XXXXXX")"
    {
      cat "$ROLE_FILE"
      printf '\n%s\n' "$DIRECTIVE"
      printf '\n\n--- [REJECTION CONTEXT] ---\n'
      printf 'The **%s** phase was REJECTED by the human reviewer.\n' "$rej_phase"
      printf 'Rejection detail: %s\n\n' "$rej_detail"
      printf 'Recent pipeline events:\n'
      flowai_event_format_for_prompt 20
      printf '\n\nYour task: Analyze why the rejection occurred. Review the artifacts '
      printf 'in the specs/ directory. Provide guidance on how to fix the issue, '
      printf 'or revise the spec if the original requirements were unclear.\n'
      printf 'When ready, signal the revision by explaining what you changed.\n\n'
      printf 'MEMORY LEARNING: Also analyze the user feedback for reusable behavioral\n'
      printf 'rules (not task-specific). If you detect one, ask the user whether to\n'
      printf 'persist it to project memory at: %s\n' "$MEMORY_FILE"
      printf 'Only write to that file if the user explicitly approves.\n---\n'
    } > "$context_prompt"

    flowai_event_emit "master" "re-engaged" "Responding to $rej_phase rejection"
    flowai_ai_run "master" "$context_prompt" "true"
    rm -f "$context_prompt"

    # Auto-signal revision ready — Master has provided guidance, unblock the phase
    touch "$SIGNALS_DIR/${rej_phase}.revision.ready" 2>/dev/null || true
    flowai_event_emit "master" "revision_signalled" "Master unblocked $rej_phase revision"
    log_info "Revision signal sent — $rej_phase phase will re-run."
  fi

  # ── Pipeline complete ──
  local completion
  completion="$(printf '%s' "$new_events" | grep '"phase":"review"' | grep '"event":"phase_complete"' || true)"
  if [[ -n "$completion" ]]; then
    printf '\n'
    flowai_event_emit "master" "pipeline_complete" "All phases done"
    log_success "Pipeline complete! All phases approved."
    log_info "Review the final artifacts in specs/ and the implemented code."
    printf '\n'
    log_info "Next steps:"
    log_info "  1. Review changes:  git diff"
    log_info "  2. Commit changes:  git add -A && git commit -m 'feat: ...'"
    log_info "  3. Update graph:    flowai graph update"
    log_info "  4. Push:            git push"
    printf '\n'
    log_success "🎉 Happy FlowAI! Feature complete."
    return 1  # Signal to exit the monitor loop
  fi

  return 0
}

while [[ "$_master_interrupted" -eq 0 ]]; do
  _master_display_status
  if ! _master_check_events; then
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
