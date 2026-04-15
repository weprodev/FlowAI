#!/usr/bin/env bash
# FlowAI - Master Phase
#
# The Master Agent is the central orchestrator of the entire pipeline.
#
#   Phase 1: Interactive spec creation — user directs the AI, approves spec
#            in conversation (AI writes approval marker), pipeline auto-advances.
#   Phase 2: Active pipeline orchestration — Master controls phase transitions,
#            reviews downstream artifacts, AI-reviews tasks (one-shot), and runs
#            the final implementation sign-off after QA (Review), then impl.ready.
#
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/ai.sh"
source "$FLOWAI_HOME/src/core/phase.sh"

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

# Master → Tasks: single-round binding review (VERDICT in one AI call).
# Previously used a two-round protocol (R1 opinion → Tasks AGREE/CONTEST → R2 VERDICT)
# which added 2 extra AI calls (~2-4 min each) with negligible practical value.
readonly _MASTER_TASKS_DISPUTE_ROUND="${FLOWAI_DIR}/signals/tasks.dispute_round"
readonly _MASTER_TASKS_VERDICT_DONE="${FLOWAI_DIR}/signals/tasks.verdict_complete"

_master_tasks_clear_review_state() {
  rm -f "$_MASTER_TASKS_VERDICT_DONE" 2>/dev/null || true
}

# Single-round binding review: Master reads spec+plan+tasks → issues VERDICT.
_master_tasks_run_verdict() {
  [[ -f "$_MASTER_TASKS_VERDICT_DONE" ]] && return 0
  [[ -f "${FLOWAI_DIR}/signals/tasks.master_approved.ready" ]] && return 0
  [[ -f "$FEATURE_DIR/tasks.md" ]] && [[ -s "$FEATURE_DIR/tasks.md" ]] || return 0

  flowai_phase_focus "master" 2>/dev/null || true
  log_header "📋 Master Agent: Reviewing Tasks Breakdown"
  log_info "Single-round binding review — issuing VERDICT..."

  local verdict_prompt
  verdict_prompt="$(mktemp "${TMPDIR:-/tmp}/flowai_master_tasks_verdict_XXXXXX")"
  {
    printf '%s\n' 'You are the Master Agent reviewing a task breakdown.'
    printf '%s\n' 'Issue exactly ONE binding verdict on whether tasks.md may proceed to implementation.'
    printf '\n%s\n' '--- spec.md ---'
    cat "$FEATURE_DIR/spec.md" 2>/dev/null || printf '(not found)\n'
    printf '\n%s\n' '--- plan.md ---'
    cat "$FEATURE_DIR/plan.md" 2>/dev/null || printf '(not found)\n'
    printf '\n%s\n' '--- tasks.md ---'
    cat "$FEATURE_DIR/tasks.md"
    printf '\n%s\n' '---'
    printf '%s\n' 'Review checklist:'
    printf '%s\n' '  - All spec acceptance criteria covered by at least one task'
    printf '%s\n' '  - Tasks align with plan architecture decisions'
    printf '%s\n' '  - Tasks are atomic (1-3 files each, clear deliverable)'
    printf '%s\n' '  - No scope creep beyond spec.md'
    printf '%s\n' 'Rules:'
    printf '%s\n' '- APPROVE if tasks.md satisfactorily covers spec+plan — minor imperfections are OK.'
    printf '%s\n' '- REJECT only for genuine gaps: missing acceptance criteria, spec violations, or tasks so vague they cannot be implemented.'
    printf '%s\n' '- Avoid perfectionism — prefer APPROVED with a short note over REJECTED for style preferences.'
    printf '%s\n' 'Your LAST LINE must be exactly one of:'
    printf '%s\n' '  VERDICT: APPROVED'
    printf '%s\n' '  VERDICT: REJECTED — <one-line reason>'
    printf '%s\n' 'Do not add anything after the verdict line.'
    printf '%s\n' 'This is a VERBAL verdict — do NOT create any files.'
    flowai_phase_artifact_boundary "master"
  } > "$verdict_prompt"

  local tasks_verdict
  tasks_verdict="$(flowai_ai_run_oneshot "master" "$verdict_prompt" || echo 'VERDICT: REJECTED — AI review failed (tool error)')"
  rm -f "$verdict_prompt"

  printf '\n'
  log_info "── Master AI — Tasks Review ──"
  printf '%s\n' "$tasks_verdict"
  printf '\n'

  local verdict_line
  verdict_line="$(printf '%s' "$tasks_verdict" | tail -1 | sed 's/^[[:space:]]*//')"
  local is_approved=false
  if [[ "$verdict_line" =~ ^[[:space:]]*VERDICT:[[:space:]]*APPROVED[[:space:]]*$ ]]; then
    is_approved=true
  elif printf '%s\n' "$tasks_verdict" | grep -qiE '^[[:space:]]*VERDICT:[[:space:]]*APPROVED[[:space:]]*$'; then
    is_approved=true
  fi

  if $is_approved; then
    rm -f "$_MASTER_TASKS_DISPUTE_ROUND" 2>/dev/null || true
    touch "${FLOWAI_DIR}/signals/tasks.master_approved.ready"
    flowai_event_emit "master" "tasks_reviewed" "Master AI approved tasks"
    log_success "✅ Tasks APPROVED. Implementation phase will begin shortly..."
  else
    local max_disputes dispute_n reject_reason
    max_disputes="${FLOWAI_TASKS_MAX_DISPUTE_ROUNDS:-3}"
    dispute_n=0
    if [[ -f "$_MASTER_TASKS_DISPUTE_ROUND" ]]; then
      dispute_n="$(tr -d '[:space:]' < "$_MASTER_TASKS_DISPUTE_ROUND" 2>/dev/null || printf '0')"
    fi
    [[ "$dispute_n" =~ ^[0-9]+$ ]] || dispute_n=0
    dispute_n=$((dispute_n + 1))

    if [[ "$dispute_n" -ge "$max_disputes" ]]; then
      log_warn "Tasks dispute limit reached ($max_disputes consecutive REJECTs). Master escalating — approving tasks.md so Implement can proceed."
      flowai_event_emit "master" "tasks_escalated" "Master forced tasks approval after $max_disputes rejections"
      {
        printf '\n\n---\n\n## FlowAI — Master escalation\n\n'
        printf 'Approved automatically after %s consecutive Master REJECT verdicts on tasks.md.\n' "$max_disputes"
        printf 'Edit this file if the checklist still needs work; Implementation was blocked until tasks.ready.\n\n'
      } >> "$FEATURE_DIR/tasks.md"
      rm -f "$_MASTER_TASKS_DISPUTE_ROUND" 2>/dev/null || true
      touch "${FLOWAI_DIR}/signals/tasks.master_approved.ready"
      log_success "✅ Tasks APPROVED (escalation). Implementation phase will begin shortly..."
    else
      printf '%s\n' "$dispute_n" > "$_MASTER_TASKS_DISPUTE_ROUND"
      reject_reason="$(printf '%s' "$tasks_verdict" | grep -i 'VERDICT:.*REJECTED' | head -1 || printf '%s' "$tasks_verdict" | tail -3)"
      log_warn "❌ Tasks REJECTED ($dispute_n/$max_disputes): $reject_reason"
      log_info "Sending revision request back to Tasks agent..."
      flowai_event_emit "master" "tasks_revision_needed" "$reject_reason"
      printf '%s\n' "$reject_reason" > "${FLOWAI_DIR}/signals/tasks.rejection_context" 2>/dev/null || true
    fi
  fi
  touch "$_MASTER_TASKS_VERDICT_DONE"
}

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

OUTPUT FILE — the canonical specification MUST end up at this exact path:
  $SPEC_FILE

PLACEHOLDER (branch bootstrap):
- $SPEC_FILE may exist with only a title line and a short \"placeholder\" paragraph from FlowAI init.
- That is NOT the real specification. Do NOT ask the user to approve placeholder text.
- Do NOT present ## Overview / acceptance criteria / checklists until after clarification unless the user already gave a complete brief.

STAGED WORKFLOW — strict order:
1) CLARIFY FIRST: Welcome briefly, then ask what they want to build (problem, goals, audience, scope, constraints).
   Your first replies should be questions and short acknowledgements — not a full spec document.
   If they already pasted full requirements, acknowledge and move to step 2.
2) WRITE THE SPEC: Only once intent is clear, replace $SPEC_FILE with the full specification
   (overview, scope, acceptance criteria, non-goals, constraints as appropriate).
3) REQUEST APPROVAL: Point to the file path, ask them to read it, then follow APPROVAL PROTOCOL below.

OPENING TURN — user guidance:
- Your FIRST reply in this session MUST briefly welcome the user and ask them to explain
  what they want to build: problem, goals, audience, scope, and constraints — in their own words.
- If they already pasted requirements or pointed you at an existing spec.md, acknowledge that
  and proceed; do not re-ask unnecessarily.
- Only after you understand their intent should you draft or revise spec.md into the full artifact.

APPROVAL PROTOCOL:
- After the full specification is written to $SPEC_FILE, tell the user the exact file path and ask them to review it.
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

MASTER_TOOL_PAIR="$(flowai_ai_resolve_tool_and_model_for_phase "master")"
MASTER_TOOL="${MASTER_TOOL_PAIR%%:*}"

# ─── Background Approval Watcher ────────────────────────────────────────────
# Polls for BOTH spec.md AND the user approval marker. Only emits spec.ready
# when the user has explicitly approved through the AI conversation.
# This ensures the user MUST approve before the pipeline advances.
# When approved, terminates the foreground Gemini REPL (via parent PID)
# so the Master automatically transitions to the monitoring loop.
_master_approval_watcher() {
  local spec_file="$1"
  local approval_marker="$2"
  local parent_pid="$3"
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
      # Handoff message is printed once below (after spec gate) so chat + manual paths match.
      # Switch focus to Plan pane
      flowai_phase_focus "plan" 2>/dev/null || true
      # Terminate the foreground Gemini process (child of our parent)
      # This allows master.sh to proceed past the blocking flowai_ai_run call.
      sleep 2  # Brief grace period for Gemini to flush output
      local child_pids
      child_pids="$(pgrep -P "$parent_pid" 2>/dev/null || true)"
      for cpid in $child_pids; do
        kill "$cpid" 2>/dev/null || true
      done
      return 0
    fi
    sleep 3
  done
}

# If spec was already approved during session resume, skip the interactive session entirely.
if [[ -f "${FLOWAI_DIR}/signals/spec.ready" ]]; then
  log_success "Spec already approved (resumed). Skipping interactive session."
  _watcher_pid=""
else

_master_approval_watcher "$SPEC_FILE" "$APPROVAL_MARKER" "$$" &
_watcher_pid=$!

_master_print_spec_session_start() {
  log_header "Specification — start here"
  log_info "If $SPEC_FILE is only a placeholder, ignore it — Master clarifies first, then writes the real spec, then asks for approval."
  log_info "Explain what you want to build: problem, goals, audience, scope, and constraints."
  log_info "When the full spec is written and you approve in chat (e.g. 'approved'), the pipeline moves to Plan."
  printf '\n'
}

# Brief grace so a marker written as an interactive REPL exits is still observed.
_master_spec_grace_poll() {
  local g=0
  while [[ ! -f "${FLOWAI_DIR}/signals/spec.ready" ]] && [[ "$g" -lt 15 ]]; do
    sleep 1
    g=$((g + 1))
  done
}

# Cursor/Copilot: no REPL in this pane — user pastes the prompt into the IDE; keep waiting for marker + spec.
_master_wait_paste_only_spec_approval() {
  if [[ "${FLOWAI_SPEC_MANUAL_NOW:-0}" == "1" ]]; then
    log_info "FLOWAI_SPEC_MANUAL_NOW=1 — skipping IDE wait; opening manual approval next."
    return 0
  fi
  local max_sec="${FLOWAI_SPEC_PASTE_WAIT_SEC:-1200}"
  log_header "Clarify the spec (in your editor)"
  log_info "Master is set to tool: $MASTER_TOOL (paste-only — no chat REPL in this tmux pane)."
  log_info "Paste the prompt above into Cursor/Copilot: clarify first (questions), then overwrite $SPEC_FILE with the full spec, then seek approval."
  log_info "Do not treat the placeholder in spec.md as something to sign off — replace it with the real specification first."
  log_info "When the user approves in chat, the agent must write the marker: $APPROVAL_MARKER"
  log_info "This pane waits for that approval (Plan stays blocked until then). Manual menu comes later if needed."
  local e=0
  while [[ ! -f "${FLOWAI_DIR}/signals/spec.ready" ]]; do
    if [[ "$max_sec" -gt 0 ]] && [[ "$e" -ge "$max_sec" ]]; then
      log_warn "No approval within ${max_sec}s — opening manual approval. Or set FLOWAI_SPEC_PASTE_WAIT_SEC=0 to wait indefinitely."
      break
    fi
    sleep 2
    e=$((e + 2))
    if (( e % 60 == 0 )); then
      log_info "Still waiting for spec approval (IDE session → marker file)… (${e}s)"
    fi
  done
}

_master_print_spec_session_start
flowai_ai_run "master" "$INJECTED_PROMPT" "true" || true  # Tolerate kill signal

# Keep the watcher alive until spec.ready — paste-only tools return immediately; killing the
# watcher here caused an instant gum menu before the user could collaborate in the IDE.

_master_spec_grace_poll

if [[ ! -f "${FLOWAI_DIR}/signals/spec.ready" ]] && flowai_ai_tool_is_paste_only "$MASTER_TOOL"; then
  _master_wait_paste_only_spec_approval
fi

# Fallback: interactive REPL ended without marker, or paste-only wait timed out.
if [[ ! -f "${FLOWAI_DIR}/signals/spec.ready" ]]; then
  log_warn "Spec approval not detected yet. Use the manual gate only after spec.md reflects real intent (not the raw template)."
  while true; do
    flowai_phase_verify_artifact "$SPEC_FILE" "Specification" "spec"
    _spec_rc=$?
    if [[ "$_spec_rc" -eq 0 ]]; then
      flowai_event_emit "master" "phase_complete" "Spec approved — pipeline advancing to Plan"
      flowai_phase_focus "plan" 2>/dev/null || true
      break
    fi
    if [[ "$_spec_rc" -eq 2 ]]; then
      flowai_event_emit "master" "rejected" "Human rejected spec — revise spec.md then approve"
    fi
    if flowai_ai_tool_is_paste_only "$MASTER_TOOL"; then
      log_info "Edit $SPEC_FILE in your editor, then return here and choose Approve (or paste the prompt again to re-print the directive)."
      _master_print_spec_session_start
      flowai_ai_run "master" "$INJECTED_PROMPT" "true" || true
    else
      log_warn "Re-entering interactive session for spec revision..."
      _master_print_spec_session_start
      flowai_ai_run "master" "$INJECTED_PROMPT" "true" || true
    fi
  done
fi

kill "${_watcher_pid:-}" 2>/dev/null || true
[[ -n "${_watcher_pid:-}" ]] && wait "$_watcher_pid" 2>/dev/null || true

# Clean up the approval marker for potential re-runs
rm -f "$APPROVAL_MARKER" 2>/dev/null || true

fi  # end spec resume guard

# ─── Phase 2: Active Pipeline Orchestration ─────────────────────────────────
# The Master is now the central brain. It actively monitors phase transitions,
# reviews downstream artifacts, AI-reviews tasks (one-shot), and mediates final
# implementation sign-off after QA (Review) — then touches impl.ready.

log_success "Spec approved. I'm handing off to the Plan agent and will stay here to monitor the pipeline."
printf '\n'
log_header "Master Agent — Pipeline Orchestrator"
log_info "Monitoring phase transitions and status in this pane. Press Ctrl+C to exit when finished."

_master_last_processed_line=0
_master_last_pipeline_line=""
_master_interrupted=0
_master_post_qa_signoff=0
_master_orchestration_start_sec=$SECONDS
# Phase timing + scope flags (indexed arrays — Bash 3.2–safe; no declare -A).
# Parallel: _master_phase_keys[i] ↔ _master_phase_starts[i] ↔ _master_scope_flags[i]
_master_phase_keys=()
_master_phase_starts=()
_master_scope_flags=()
trap '_master_interrupted=1' INT TERM

# Dirty-tracking: suppresses \r-overwrite when other output has displaced the cursor.
_master_status_dirty=false

_master_mark_display_dirty() {
  _master_status_dirty=true
}

_master_display_status() {
  local status line
  status="$(flowai_event_pipeline_status)"
  if [[ -z "$status" || "$status" == "{}" ]]; then
    return 0
  fi
  line="$(printf '%s' "$status" | jq -r 'to_entries | map("\(.key)=\(.value)") | join(" · ")' 2>/dev/null || echo "$status")"
  line="$(flowai_sanitize_display_text "$line")"

  local elapsed=$(( SECONDS - _master_orchestration_start_sec ))
  local frame
  frame="$(flowai_spinner_frame)"

  # Status changed → print as a permanent log line, then reset for spinner
  if [[ "$line" != "${_master_last_pipeline_line:-}" ]]; then
    # Clear any leftover spinner line before printing the new status
    if ! flowai_terminal_plain_enabled; then
      flowai_clear_line
    fi
    log_info "Pipeline: $line"
    _master_last_pipeline_line="$line"
    _master_status_dirty=false
    return 0
  fi

  # Status unchanged — show spinner on a single overwritten line (non-plain terminals only)
  if flowai_terminal_plain_enabled; then
    return 0
  fi

  # If something else printed output since the last spinner draw, skip the \r overwrite
  # for one cycle to avoid corrupting the previous output line.
  if [[ "$_master_status_dirty" == "true" ]]; then
    _master_status_dirty=false
    return 0
  fi

  # Overwrite the current line with spinner + elapsed time
  local mins=$(( elapsed / 60 ))
  local secs=$(( elapsed % 60 ))
  local time_str
  if [[ "$mins" -gt 0 ]]; then
    time_str="${mins}m${secs}s"
  else
    time_str="${secs}s"
  fi
  flowai_overwrite_line "$(printf '%s%s  Monitoring pipeline · %s%s' "$CYAN" "$frame" "$time_str" "$RESET")"
}

_master_emit_pipeline_complete_message() {
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

  # Write the tmux session name into the signal file so the teardown at the
  # end of this script and the host wrapper (start.sh) can use it reliably.
  # We compute it here while all sourced functions are still available.
  {
    source "$FLOWAI_HOME/src/core/session.sh"
    flowai_session_name "$(flowai_repo_root_for_session)"
  } > "${FLOWAI_DIR}/signals/pipeline.complete" 2>/dev/null || touch "${FLOWAI_DIR}/signals/pipeline.complete"
}

# Agent-agnostic: any phase may emit event "error" — offer recovery (stop / continue / exit monitoring).
# Reads new JSONL batch; returns 0, or 2 if user chose to exit Master monitoring only.
# Returns nothing if FLOWAI_TESTING=1 (logs only).
_master_handle_phase_errors_from_batch() {
  local new_events="$1"
  local line ev_phase ev_detail choice
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    command -v jq >/dev/null 2>&1 || return 0
    [[ "$(jq -r '.event // empty' <<< "$line" 2>/dev/null)" == "error" ]] || continue
    ev_phase="$(jq -r '.phase // "unknown"' <<< "$line" 2>/dev/null)"
    ev_detail="$(jq -r '.detail // ""' <<< "$line" 2>/dev/null)"

    printf '\n'
    log_header "Phase error — $ev_phase"
    log_error "A pipeline phase reported failure."
    [[ -n "$ev_detail" ]] && log_warn "Detail: $ev_detail"
    flowai_phase_focus "$ev_phase" 2>/dev/null || true

    if [[ "${FLOWAI_TESTING:-0}" == "1" ]]; then
      log_warn "($ev_phase error — recovery menu skipped in FLOWAI_TESTING)"
      continue
    fi

    log_info "How do you want to proceed?"
    if command -v gum >/dev/null 2>&1; then
      choice="$(flowai_gum_choose --header "  Recovery" \
        'Stop FlowAI session (flowai stop) — kill tmux, start fresh later' \
        'Continue monitoring — I will fix artifacts or re-run the phase, then use the normal approval gates' \
        'Exit Master monitoring only — leave other panes running')"
    else
      printf '%s\n' "  1) Stop FlowAI session (flowai stop) — kill tmux" \
        "  2) Continue monitoring — fix / re-run phase, then approve as usual" \
        "  3) Exit Master monitoring only"
      read -r -p "Choice [1-3]: " choice < /dev/tty || true
      case "$choice" in
        1) choice="Stop FlowAI session" ;;
        3) choice="Exit Master monitoring only" ;;
        *) choice="Continue monitoring" ;;
      esac
    fi

    case "$choice" in
      Stop*)
        flowai_event_emit "master" "error_recovery" "User chose flowai stop after $ev_phase error"
        log_info "Stopping FlowAI session…"
        FLOWAI_KILL_NO_CONFIRM=1 bash "$FLOWAI_HOME/src/commands/kill.sh"
        exit 0
        ;;
      *Exit*Master*|*Exit*monitoring*)
        flowai_event_emit "master" "error_recovery" "User exited Master monitoring after $ev_phase error"
        log_info "Exiting Master monitoring."
        return 2
        ;;
      *)
        flowai_event_emit "master" "error_recovery" "User chose to continue after $ev_phase error"
        local _run_hint="$ev_phase"
        [[ "$_run_hint" == "impl" ]] && _run_hint="implement"
        log_info "Continuing. When ready, re-run the failed work if needed, e.g.:  flowai run $_run_hint"
        log_info "Then use the usual human approval gates in each phase pane."
        ;;
    esac
  done < <(printf '%s\n' "$new_events")
  return 0
}

# ── Scope/time monitoring ─────────────────────────────────────────────────────
# Track when phases start (via "started" events) and run a scope check if a
# phase exceeds FLOWAI_PHASE_EXPECTED_DURATION_SEC (default: 300s / 5 min).
# The check runs once per phase per session.

_master_record_phase_start() {
  local new_events="$1"
  local _evt_line _evt_phase _evt_event i idx
  while IFS= read -r _evt_line; do
    [[ -z "$_evt_line" ]] && continue
    _evt_event="$(jq -r '.event // empty' <<< "$_evt_line" 2>/dev/null)" || continue
    [[ "$_evt_event" == "started" ]] || continue
    _evt_phase="$(jq -r '.phase // empty' <<< "$_evt_line" 2>/dev/null)" || continue
    [[ -n "$_evt_phase" ]] || continue
    idx=-1
    for i in "${!_master_phase_keys[@]}"; do
      if [[ "${_master_phase_keys[$i]}" == "$_evt_phase" ]]; then
        idx=$i
        break
      fi
    done
    if [[ "$idx" -ge 0 ]]; then
      _master_phase_starts[idx]=$SECONDS
    else
      _master_phase_keys+=("$_evt_phase")
      _master_phase_starts+=("$SECONDS")
      _master_scope_flags+=("0")
    fi
  done < <(printf '%s\n' "$new_events")
}

_master_run_scope_check() {
  local phase="$1"
  local elapsed="$2"

  local scope_prompt
  scope_prompt="$(mktemp "${TMPDIR:-/tmp}/flowai_master_scope_XXXXXX")"
  {
    printf 'You are the Master Agent performing a scope check.\n'
    printf 'The "%s" phase has been running for %ds, which exceeds the expected %ds.\n\n' \
      "$phase" "$elapsed" "${FLOWAI_PHASE_EXPECTED_DURATION_SEC:-300}"
    printf 'Read the spec:\n  %s/spec.md\n\n' "$FEATURE_DIR"
    printf 'Check what the %s phase should be doing vs what it appears to be doing.\n' "$phase"
    printf 'Is the agent doing ONLY what is expected for this phase, or has it gone beyond scope?\n\n'
    printf 'Reply with ONE line:\n'
    printf '  SCOPE: ON_TRACK — <brief reason>\n'
    printf '  SCOPE: OVER_SCOPE — <what extra work the agent appears to be doing>\n'
    printf 'This is a VERBAL check — do NOT create any files.\n'
    flowai_phase_artifact_boundary "master"
  } > "$scope_prompt"

  local scope_result
  scope_result="$(flowai_ai_run_oneshot "master" "$scope_prompt" 2>/dev/null || echo 'SCOPE: UNKNOWN — AI check failed')"
  rm -f "$scope_prompt"

  if printf '%s' "$scope_result" | grep -qi 'OVER_SCOPE'; then
    log_warn "Scope check: $phase appears OVER SCOPE"
    printf '%s\n' "$scope_result"
    flowai_event_emit "master" "scope_warning" "Phase $phase may be exceeding its mandate"
  else
    log_info "Scope check: $phase is ON TRACK (just slow)"
    flowai_event_emit "master" "scope_ok" "Phase $phase on track despite long runtime"
  fi
}

_master_check_phase_durations() {
  [[ "${FLOWAI_TESTING:-0}" != "1" ]] || return 0
  local max_sec="${FLOWAI_PHASE_EXPECTED_DURATION_SEC:-300}"
  local i phase start_sec elapsed n

  n=${#_master_phase_keys[@]}
  for (( i = 0; i < n; i++ )); do
    phase="${_master_phase_keys[$i]}"
    start_sec="${_master_phase_starts[$i]}"
    [[ -n "$start_sec" && "$start_sec" =~ ^[0-9]+$ ]] || continue

    # Skip if already scope-checked or phase is complete
    [[ "${_master_scope_flags[$i]}" == "1" ]] && continue
    [[ ! -f "${FLOWAI_DIR}/signals/${phase}.ready" ]] || continue

    elapsed=$(( SECONDS - start_sec ))
    if [[ "$elapsed" -gt "$max_sec" ]]; then
      _master_scope_flags[i]=1
      log_warn "Phase '$phase' has been running for ${elapsed}s (threshold: ${max_sec}s). Running scope check..."
      flowai_event_emit "master" "scope_check" "Phase $phase exceeded ${max_sec}s (elapsed: ${elapsed}s)"
      _master_run_scope_check "$phase" "$elapsed"
    fi
  done
}

_master_check_events() {
  [[ -f "$FLOWAI_EVENTS_FILE" ]] || return 0

  # Rejection handler assigns these; initialize so 'set -u' never sees an unbound name.
  local rej_phase="" rej_detail=""

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

  # Record phase start times for scope monitoring
  _master_record_phase_start "$new_events"

  local _err_rc=0
  _master_handle_phase_errors_from_batch "$new_events" || _err_rc=$?
  [[ "$_err_rc" -eq 2 ]] && return 2

  # ── Plan phase approved → switch focus to Tasks ──
  local plan_approved
  plan_approved="$(printf '%s' "$new_events" | grep '"phase":"plan"' | grep '"event":"phase_complete"' || true)"
  if [[ -n "$plan_approved" ]]; then
    printf '\n'
    log_success "Plan phase approved. Preparing Tasks phase..."
    flowai_phase_focus "tasks" 2>/dev/null || true
  fi

  # ── Implementation produced code → Review (QA) runs next; keep focus on Review, not Master ──
  local impl_produced_evt
  impl_produced_evt="$(printf '%s' "$new_events" | grep '"phase":"impl"' | grep '"event":"impl_produced"' || true)"
  if [[ -n "$impl_produced_evt" ]] && [[ ! -f "${FLOWAI_DIR}/signals/impl.ready" ]]; then
    flowai_phase_focus "review" 2>/dev/null || true
  fi

  # ── Tasks phase interrupted (e.g. Ctrl+C) — unblock guidance ──
  local tasks_aborted
  tasks_aborted="$(printf '%s' "$new_events" | grep '"phase":"tasks"' | grep '"event":"phase_aborted"' || true)"
  if [[ -n "$tasks_aborted" ]]; then
    printf '\n'
    log_warn "Tasks phase ended without Master approval — Implement may stay blocked on tasks.ready."
    log_info "Recovery: edit tasks.md if needed, then run:  touch ${FLOWAI_DIR}/signals/tasks.master_approved.ready"
    log_info "Or re-run the phase:  flowai run tasks"
  fi

  # ── Tasks produced → Master single-round binding VERDICT ──
  local tasks_ready
  tasks_ready="$(printf '%s' "$new_events" | grep '"phase":"tasks"' | grep '"event":"tasks_produced"' || true)"
  if [[ -n "$tasks_ready" ]]; then
    printf '\n'
    if [[ -f "$FEATURE_DIR/tasks.md" ]] && [[ -s "$FEATURE_DIR/tasks.md" ]]; then
      _master_tasks_clear_review_state
      _master_tasks_run_verdict
    else
      log_warn "tasks.md not found or empty — waiting for Tasks agent to produce it."
    fi
  fi

  # ── QA complete (Review) → Master final sign-off → impl.ready → pipeline complete ──
  local review_qa_done
  review_qa_done="$(printf '%s' "$new_events" | grep '"phase":"review"' | grep '"event":"phase_complete"' || true)"
  if [[ -n "$review_qa_done" ]] && [[ ! -f "${FLOWAI_DIR}/signals/impl.ready" ]] && [[ "$_master_post_qa_signoff" -eq 0 ]]; then
    _master_post_qa_signoff=1
    printf '\n'
    flowai_phase_focus "master" 2>/dev/null || true
    log_header "QA Complete — Master Final Sign-off"
    log_info "Review (QA) approved. Showing change summary, then Master binding review, then your approval."
    printf '\n'

    log_info "── Code changes (summary) — printed here so you can scroll in tmux (no pager) ──"
    local _diff_sum
    _diff_sum="$(flowai_git_diff_stat_head)"
    if [[ -n "${_diff_sum}" ]]; then
      printf '%s\n' "${_diff_sum}"
    else
      log_warn "(git diff unavailable or no tracked changes vs HEAD)"
    fi
    printf '\n'

    # Capture review output to detect NEEDS_FOLLOW_UP verdict
    local _review_output_file
    _review_output_file="$(mktemp "${TMPDIR:-/tmp}/flowai_master_review_output_XXXXXX")"

    local review_prompt
    review_prompt="$(mktemp "${TMPDIR:-/tmp}/flowai_master_review_XXXXXX")"
    {
      cat "$ROLE_FILE"
      printf '\n%s\n' "$DIRECTIVE"
      printf '\n\n--- [POST-QA MASTER SIGN-OFF] ---\n'
      printf 'Review (QA) has already approved in the Review pane.\n'
      printf 'You are performing the **final** Master orchestration review before the\n'
      printf 'implementation phase may exit (impl.ready).\n'
      printf "The human has already seen \`git diff --stat\` above — do not ask them to run it.\n"
      printf '\nReview the following artifacts:\n'
      printf '  spec.md:   %s\n' "$FEATURE_DIR/spec.md"
      printf '  plan.md:   %s\n' "$FEATURE_DIR/plan.md"
      printf '  tasks.md:  %s\n' "$FEATURE_DIR/tasks.md"
      # Include the QA report so Master has the Review agent's findings
      if [[ -f "$FEATURE_DIR/review.md" ]]; then
        printf '  review.md: %s\n' "$FEATURE_DIR/review.md"
        printf '\n--- review.md (QA report) ---\n'
        cat "$FEATURE_DIR/review.md"
        printf '\n---\n'
      fi
      printf '\nReview the code changes (tests/linters as appropriate).\n'
      printf '\nIMPORTANT: This is a VERBAL review only. Do NOT create any files.\n'
      printf 'Do NOT create plan files, review documents, or any other artifacts.\n'
      printf 'Output your review directly in the conversation.\n'
      printf '\n--- [REQUIRED OUTPUT SHAPE — single response, in conversation only] ---\n'
      printf '1) ## Master — review checklist (bullets: checks vs spec/plan/tasks)\n'
      printf '2) ## Master — findings (Spec compliance | Plan alignment | Tasks | Quality | Risks)\n'
      printf '3) ## Master — verdict\n'
      printf '   - One line: READY_FOR_HUMAN_SIGNOFF | NEEDS_FOLLOW_UP\n'
      printf '   - If NEEDS_FOLLOW_UP: say which phase should act next (impl / review)\n'
      printf '     and describe EXACTLY what must change — this text will be sent directly\n'
      printf '     to the Implement agent as revision context.\n'
      printf '   - If READY_FOR_HUMAN_SIGNOFF: say so clearly.\n'
      printf '4) Short recommendation for the human.\n'
      printf '\nProduce the full review in this one response. Do NOT write it to a file.\n---\n'
      flowai_phase_artifact_boundary "master"
    } > "$review_prompt"

    flowai_event_emit "master" "reviewing_impl" "Master final sign-off after QA"
    log_info "── Master AI — binding review (oneshot; output streams live to this pane) ──"
    log_info "    (If nothing prints for a while, the CLI may still be working — with Gemini, stderr shows a heartbeat every ${FLOWAI_GEMINI_ONESHOT_HEARTBEAT_SEC:-8}s.)"
    # Tee output to both terminal (live streaming) and capture file (verdict detection)
    set +e
    flowai_ai_run_oneshot "master" "$review_prompt" | tee "$_review_output_file"
    local _review_oneshot_rc=${PIPESTATUS[0]}
    set -e
    rm -f "$review_prompt"
    if [[ "$_review_oneshot_rc" -ne 0 ]]; then
      log_warn "Master binding oneshot exited with status ${_review_oneshot_rc} — continue with the approval step if the review text above is acceptable."
    fi
    printf '\n'

    # Check if Master AI flagged NEEDS_FOLLOW_UP — auto-send revision to Implement
    local _master_verdict_needs_followup=false
    if grep -qiE 'NEEDS_FOLLOW_UP' "$_review_output_file" 2>/dev/null; then
      _master_verdict_needs_followup=true
    fi

    if $_master_verdict_needs_followup; then
      log_warn "Master AI verdict: NEEDS_FOLLOW_UP — sending revision context to Implement agent."
      # Extract the findings + verdict as revision context for Implement
      {
        printf '## Master Post-QA Review — Revision Required\n\n'
        printf 'The Master Agent reviewed the implementation after QA and found issues.\n'
        printf 'Fix the issues below, then the pipeline will re-run QA and Master review.\n\n'
        cat "$_review_output_file"
      } > "${FLOWAI_DIR}/signals/impl.rejection_context"
      rm -f "$_review_output_file"
      flowai_event_emit "master" "impl_revision_needed" "Master post-QA review: NEEDS_FOLLOW_UP"
      # Reset so we re-enter post-QA flow after impl + review cycle completes
      _master_post_qa_signoff=0
      # Also reset impl.code_complete so Review will re-run after impl finishes
      rm -f "${FLOWAI_DIR}/signals/impl.code_complete.ready" 2>/dev/null || true
      log_info "Revision context sent to Implement. Waiting for impl → review → Master cycle..."
      flowai_phase_focus "impl" 2>/dev/null || true
    else
      rm -f "$_review_output_file"
      log_info "── Human approval gate (not AI) — choose in the menu below ──"
      log_info "    Use ↑/↓ and Enter. If the screen looks noisy (OSC codes), the menu is still active — pick an option."
      # omit_git_stat=1: diff stat was already printed above (avoid duplicate + never use a tty pager)
      flowai_phase_verify_artifact "$FEATURE_DIR/tasks.md" "Implementation (post-QA Master sign-off)" "impl" "1"
      local impl_rc=$?
      if [[ "$impl_rc" -eq 0 ]]; then
        flowai_event_emit "master" "impl_approved" "Implementation approved after post-QA Master review"
        log_success "Implementation approved! Unblocking Implement phase."
        # Close Implement/Review panes first, then show next steps only on Master (phase.sh).
        flowai_session_close_non_master_panes
        _master_emit_pipeline_complete_message
        flowai_session_prompt_end
        return 1
      fi
      # User chose "Needs changes" — collect feedback and send to Implement
      if [[ "$impl_rc" -eq 2 ]]; then
        printf '\n'
        log_info "What changes are needed? (Type your feedback, then press Enter)"
        local _user_feedback=""
        if [[ -r /dev/tty ]]; then
          read -r _user_feedback </dev/tty || true
        else
          read -r _user_feedback || true
        fi
        if [[ -n "$_user_feedback" ]]; then
          {
            printf '## User Revision Request (post-QA)\n\n'
            printf 'The user reviewed the implementation after Master + QA approval and requested changes.\n\n'
            printf '### User feedback:\n%s\n' "$_user_feedback"
          } > "${FLOWAI_DIR}/signals/impl.rejection_context"
          flowai_event_emit "master" "impl_revision_needed" "User requested changes: $_user_feedback"
        else
          {
            printf '## User Revision Request (post-QA)\n\n'
            printf 'The user reviewed the implementation and requested changes (no specific details provided).\n'
            printf 'Review the spec, plan, and tasks for alignment.\n'
          } > "${FLOWAI_DIR}/signals/impl.rejection_context"
          flowai_event_emit "master" "impl_revision_needed" "User requested changes (no details)"
        fi
        # Reset so we re-enter post-QA flow after impl + review cycle completes
        _master_post_qa_signoff=0
        rm -f "${FLOWAI_DIR}/signals/impl.code_complete.ready" 2>/dev/null || true
        log_info "Revision context sent to Implement. Waiting for impl → review → Master cycle..."
        flowai_phase_focus "impl" 2>/dev/null || true
      fi
    fi
  fi

  # ── Rejection in any downstream phase ──
  local rejection
  rejection="$(printf '%s' "$new_events" | grep '"event":"rejected"' | tail -1 || true)"
  if [[ -n "$rejection" ]]; then
    rej_phase="$(printf '%s' "$rejection" | jq -r '.phase' 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    rej_detail="$(printf '%s' "$rejection" | jq -r '.detail // "No details"' 2>/dev/null)"
    if [[ -z "$rej_phase" || "$rej_phase" == "null" ]]; then
      rej_phase="unknown"
    fi

    printf '\n'
    flowai_phase_focus "master" 2>/dev/null || true
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
      flowai_phase_artifact_boundary "master"
    } > "$context_prompt"

    flowai_event_emit "master" "re-engaged" "Responding to $rej_phase rejection"
    flowai_ai_run "master" "$context_prompt" "true"
    rm -f "$context_prompt"

    # Auto-signal revision ready — Master has provided guidance, unblock the phase
    # Phase id in events must be lowercase (e.g. plan) to match .revision.ready wait paths.
    if [[ "$rej_phase" != "unknown" ]]; then
      touch "$SIGNALS_DIR/${rej_phase}.revision.ready" 2>/dev/null || true
    fi
    flowai_event_emit "master" "revision_signalled" "Master unblocked $rej_phase revision"
    log_info "Revision signal sent — $rej_phase phase will re-run."
    if [[ "$rej_phase" == "plan" ]]; then
      log_info "👉 Switching focus to Plan — re-run the architecture step with your feedback in context."
      flowai_phase_focus "plan" 2>/dev/null || true
    fi
  fi

  return 0
}

while [[ "$_master_interrupted" -eq 0 ]]; do
  _master_display_status
  _mrc=0
  _master_check_events || _mrc=$?
  _master_mark_display_dirty   # event handling may have printed log lines
  case "$_mrc" in
    0) ;;
    1) break ;; # Pipeline complete (impl approved)
    2) _master_interrupted=1; break ;; # User exited monitoring (e.g. error recovery menu)
    *) break ;;
  esac
  _master_check_phase_durations
  _master_mark_display_dirty   # scope checks may have printed warnings
  sleep "${FLOWAI_MASTER_POLL_SEC:-2}"
done

trap - INT TERM

if [[ "$_master_interrupted" -eq 1 ]]; then
  printf '\n'
  log_info "Master monitoring stopped by user."
  flowai_event_emit "master" "monitoring_stopped" "User exited monitoring or interrupted"
fi

log_info "Master Agent session ended."

# ─── Session teardown ─────────────────────────────────────────────────────────
# Kill the tmux session so the user is returned to the host terminal.
# The session name was written into pipeline.complete by the emit function.
if [[ -f "${FLOWAI_DIR}/signals/pipeline.complete" && "${FLOWAI_TESTING:-0}" != "1" ]]; then
  _flowai_session=""

  # Strategy 1: current tmux session (same as wrap-up confirm — most reliable).
  if [[ -n "${TMUX:-}" ]]; then
    _flowai_session="$(tmux display-message -p '#S' 2>/dev/null)" || true
  fi
  # Strategy 2: signal file / repo-based name (must match flowai start).
  if [[ -z "$_flowai_session" ]] || ! tmux has-session -t "$_flowai_session" 2>/dev/null; then
    _flowai_session="$(flowai_resolve_tmux_session_name)"
  fi
  # Strategy 3: any flowai-* session (last resort if detached / renamed).
  if [[ -z "$_flowai_session" ]] || ! tmux has-session -t "$_flowai_session" 2>/dev/null; then
    _flowai_session="$(tmux list-sessions -F '#S' 2>/dev/null | grep '^flowai-' | head -1)" || true
  fi

  if [[ -n "$_flowai_session" ]] && command -v tmux >/dev/null 2>&1; then
    sleep 2
    if ! tmux kill-session -t "$_flowai_session" 2>/dev/null; then
      log_warn "Could not tear down tmux session '$_flowai_session'. Try: flowai kill"
    fi
  fi
fi
