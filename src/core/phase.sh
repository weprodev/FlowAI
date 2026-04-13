#!/usr/bin/env bash
# Phase engine — signal coordination, feature dir resolution, human approval gates.
# shellcheck shell=bash

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/config.sh"
source "$FLOWAI_HOME/src/core/eventlog.sh"

export FLOWAI_DIR="${FLOWAI_DIR:-$PWD/.flowai}"
export SIGNALS_DIR="${FLOWAI_DIR}/signals"
export SPECS_DIR="${PWD}/specs"

# shellcheck source=src/core/wait_ui.sh
source "$FLOWAI_HOME/src/core/wait_ui.sh"
# shellcheck source=src/core/session.sh
source "$FLOWAI_HOME/src/core/session.sh"

if [[ ! -d "$FLOWAI_DIR" ]] || [[ ! -f "$FLOWAI_DIR/config.json" ]]; then
  log_error "Not a FlowAI project here — run: flowai init"
  exit 1
fi

# Gum reads the keyboard via stdin. When bash stdin is not the user terminal (nested
# pipelines, some tmux layouts), menus hang or leak OSC noise unless we attach /dev/tty.
flowai_gum_choose() {
  if [[ -r /dev/tty ]] && [[ -w /dev/tty ]]; then
    gum choose "$@" </dev/tty
  else
    gum choose "$@"
  fi
}

flowai_gum_pager_file() {
  local f="$1"
  if [[ -r /dev/tty ]] && [[ -w /dev/tty ]]; then
    gum pager "$f" </dev/tty
  else
    gum pager "$f"
  fi
}

# Kill every tmux pane in this FlowAI session except the current pane (typically Master).
flowai_tmux_kill_other_panes() {
  command -v tmux >/dev/null 2>&1 || return 0
  [[ -n "${TMUX:-}" ]] || return 0
  local session me w p
  session="$(tmux display-message -p '#S' 2>/dev/null)" || return 0
  me="${TMUX_PANE}"
  local -a kill_list=()
  while IFS= read -r w; do
    [[ -n "$w" ]] || continue
    while IFS= read -r p; do
      [[ -n "$p" && "$p" != "$me" ]] && kill_list+=("$p")
    done < <(tmux list-panes -t "${session}:$w" -F '#{pane_id}' 2>/dev/null)
  done < <(tmux list-windows -t "$session" -F '#{window_index}' 2>/dev/null)
  for p in "${kill_list[@]}"; do
    tmux kill-pane -t "$p" 2>/dev/null || true
  done
}

# After pipeline success: close other agent panes, wait for Enter, confirm quit → kill tmux session.
# Skipped in tests (FLOWAI_TESTING=1) or when FLOWAI_SESSION_END=0.
flowai_session_prompt_end() {
  if [[ "${FLOWAI_TESTING:-0}" == "1" ]]; then
    return 0
  fi
  if [[ "${FLOWAI_SESSION_END:-1}" == "0" ]]; then
    return 0
  fi

  printf '\n'
  log_header "Session wrap-up"
  log_info "Next steps are listed above."
  printf '\n'
  log_info "Press Enter when you have finished reading…"
  if [[ -r /dev/tty ]] && [[ -w /dev/tty ]]; then
    read -r _ </dev/tty || true
  else
    read -r _ || true
  fi

  log_info "Closing other agent panes…"
  flowai_phase_focus "master" 2>/dev/null || true
  flowai_tmux_kill_other_panes

  printf '\n'
  local do_kill=0
  if command -v gum >/dev/null 2>&1 && [[ -r /dev/tty ]] && [[ -w /dev/tty ]]; then
    if gum confirm "Quit FlowAI and close this tmux session (all windows)?" </dev/tty; then
      do_kill=1
    fi
  else
    local ans=""
    if [[ -r /dev/tty ]]; then
      read -r -p "Quit FlowAI and close this tmux session? [y/N]: " ans </dev/tty || true
    else
      read -r -p "Quit FlowAI and close this tmux session? [y/N]: " ans || true
    fi
    if [[ "$ans" =~ ^[yY]([eE][sS])?$ ]]; then
      do_kill=1
    fi
  fi

  if [[ "$do_kill" -eq 1 ]]; then
    local sess
    sess="$(flowai_session_name "$PWD")"
    if tmux has-session -t "$sess" 2>/dev/null; then
      exec tmux kill-session -t "$sess"
    fi
    exit 0
  fi
  log_info "Session left running. When finished:  flowai kill"
}

# Block until <signal>.ready exists. Respects SIGINT (exit 130) and
# FLOWAI_PHASE_TIMEOUT_SEC (0 = unlimited, the default).
flowai_phase_wait_for() {
  local signal="$1"
  local my_phase="$2"

  [[ -f "$SIGNALS_DIR/${signal}.ready" ]] && return 0

  local _wu_rank
  _wu_rank="$(flowai_wait_ui_resolve_rank "$my_phase")"

  flowai_event_emit "$my_phase" "waiting" "Blocked on ${signal}.ready"
  printf "\n${YELLOW}⏳ [%s] Waiting for '%s'...${RESET}\n" "$my_phase" "$signal"

  local _interrupted=0
  trap '_interrupted=1' INT TERM

  local _elapsed=0
  local _timeout="${FLOWAI_PHASE_TIMEOUT_SEC:-0}"
  while [[ ! -f "$SIGNALS_DIR/${signal}.ready" ]]; do
    if [[ "$_interrupted" -eq 1 ]]; then
      trap - INT TERM
      flowai_wait_ui_clear_line
      flowai_wait_ui_release_if_owner "$_wu_rank"
      log_warn "Wait interrupted — exiting ${my_phase}."
      exit 130
    fi
    if [[ "$_timeout" -gt 0 && "$_elapsed" -ge "$_timeout" ]]; then
      trap - INT TERM
      flowai_wait_ui_clear_line
      flowai_wait_ui_release_if_owner "$_wu_rank"
      log_error "Timed out after ${_timeout}s waiting for '${signal}.ready' (${my_phase})."
      log_error "Set FLOWAI_PHASE_TIMEOUT_SEC=0 to wait indefinitely."
      exit 1
    fi
    sleep 2
    _elapsed=$(( _elapsed + 2 ))
    if flowai_wait_ui_claim_or_skip "$_wu_rank"; then
      flowai_wait_ui_pulse_line "$_elapsed" 2 "${signal}.ready"
    fi
  done

  trap - INT TERM
  flowai_wait_ui_clear_line
  flowai_wait_ui_release_if_owner "$_wu_rank"
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

  # Unambiguous: when specs/<git-branch>/ exists, use it (avoids gum-choosing develop vs feature).
  local _cur_branch=""
  _cur_branch="$(git -C "${PWD}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ -n "$_cur_branch" && "$_cur_branch" != "HEAD" ]]; then
    local _preferred="${SPECS_DIR}/${_cur_branch}"
    if [[ -d "$_preferred" ]]; then
      printf '%s' "$_preferred"
      return 0
    fi
  fi

  case "${#dirs[@]}" in
    0) return 0 ;;
    1) printf '%s' "${dirs[0]}" ;;
    *)
      if [[ "${FLOWAI_TESTING:-0}" == "1" ]]; then
        printf '%s' "${dirs[0]}"
      elif command -v gum >/dev/null 2>&1; then
        flowai_gum_choose "${dirs[@]}"
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

# Print phase-specific context before the approval gate so the user knows
# exactly what they are approving. Inspired by spec-kit's approval patterns:
# show coverage metrics, change stats, and a clear "what approve means" line.
# Args: phase_id, target_file
_flowai_phase_approval_context() {
  local phase_id="$1"
  local target_file="$2"

  printf '\n'
  printf '%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$CYAN" "$RESET"

  case "$phase_id" in
    plan)
      printf '%s  PLAN REVIEW%s\n' "$BOLD" "$RESET"
      printf '  Artifact: %s\n' "$target_file"
      printf '\n'
      printf '  %sWhat you are approving:%s\n' "$BOLD" "$RESET"
      printf '  The architecture plan aligns with spec.md requirements\n'
      printf '  and provides a sound implementation strategy.\n'
      ;;
    review|impl)
      printf '%s  IMPLEMENTATION REVIEW%s\n' "$BOLD" "$RESET"
      printf '\n'
      # Git diff summary
      local diff_stat
      diff_stat="$(git diff --stat HEAD 2>/dev/null || true)"
      if [[ -n "$diff_stat" ]]; then
        printf '  %sFiles changed:%s\n' "$BOLD" "$RESET"
        printf '%s\n' "$diff_stat" | while IFS= read -r line; do
          printf '    %s\n' "$line"
        done
        printf '\n'
      fi
      # Task completion status from tasks.md
      local tasks_file
      tasks_file="$(dirname "$target_file")/tasks.md"
      if [[ -f "$tasks_file" ]]; then
        local total done_count
        total="$(grep -cE '^\s*- \[' "$tasks_file" 2>/dev/null || echo 0)"
        done_count="$(grep -cE '^\s*- \[x\]' "$tasks_file" 2>/dev/null || echo 0)"
        if [[ "$total" -gt 0 ]]; then
          local pct=$(( done_count * 100 / total ))
          printf '  %sTask completion:%s %s/%s (%s%%)\n' "$BOLD" "$RESET" "$done_count" "$total" "$pct"
          if [[ "$done_count" -lt "$total" ]]; then
            printf '  %s⚠  %s task(s) incomplete%s\n' "$YELLOW" "$(( total - done_count ))" "$RESET"
          fi
          printf '\n'
        fi
      fi
      printf '  %sWhat you are approving:%s\n' "$BOLD" "$RESET"
      printf '  The implementation satisfies the spec acceptance criteria,\n'
      printf '  follows the architecture plan, and passes QA review.\n'
      ;;
    spec)
      printf '%s  SPECIFICATION REVIEW%s\n' "$BOLD" "$RESET"
      printf '  Artifact: %s\n' "$target_file"
      printf '\n'
      printf '  %sWhat you are approving:%s\n' "$BOLD" "$RESET"
      printf '  The specification accurately captures your intent,\n'
      printf '  requirements, and acceptance criteria.\n'
      ;;
    *)
      printf '%s  %s — APPROVAL GATE%s\n' "$BOLD" "$phase_id" "$RESET"
      printf '  Artifact: %s\n' "$target_file"
      ;;
  esac

  printf '%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$CYAN" "$RESET"
}

# Prompt the human to approve a phase artifact.
# Args: target_file, artifact_label (human), phase_id (canonical — MUST match pipeline id for events, e.g. plan)
# Returns: 0 = approved, 1 = retry agent, 2 = needs changes (reject).
flowai_phase_verify_artifact() {
  local target_file="$1"
  local artifact_label="$2"
  local phase_id="$3"

  while [[ ! -f "$target_file" ]]; do
    log_error "Required output not found: $target_file"

    local action=""
    if command -v gum >/dev/null 2>&1; then
      action="$(flowai_gum_choose 'Wait (I saved it)' 'Retry Agent' 'Create empty')"
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

  flowai_event_emit "$phase_id" "artifact_produced" "$target_file"

  # Show phase-specific approval context (git diff, task status, what "approve" means)
  _flowai_phase_approval_context "$phase_id" "$target_file"

  printf '\n'

  while true; do
    local decision=""
    if command -v gum >/dev/null 2>&1; then
      log_info "⏸️  Waiting on you — interactive menu (read keyboard from terminal)…"
      decision="$(flowai_gum_choose --header "  How would you like to proceed?" 'Approve' 'Needs changes' 'Review artifact')"
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
        mode="$(flowai_gum_choose 'Read here (Terminal)' 'Open in Editor')"
        if [[ "$mode" == "Open in Editor" ]]; then
          command -v "$my_editor" >/dev/null 2>&1 || my_editor="vi"
          "$my_editor" "$target_file" </dev/tty >/dev/tty 2>&1 || true
        else
          flowai_gum_pager_file "$target_file"
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
      touch "$SIGNALS_DIR/${phase_id}.ready"
      flowai_event_emit "$phase_id" "approved" "$target_file"
      return 0
    fi

    touch "$SIGNALS_DIR/${phase_id}.reject" 2>/dev/null || true
    flowai_event_emit "$phase_id" "rejected" "Human rejected artifact"
    log_warn "Phase rejected — coordinate with Master, then resume."
    return 2
  done
}

# After a phase completes: remove this UI so remaining panes (Master / Implement) get space.
# Phases: plan | tasks | review
# - dashboard: one window, multiple panes → kill this pane (TMUX_PANE).
# - tabs: one phase per window → kill this window.
flowai_phase_schedule_close_phase_ui() {
  local phase_name="${1:-}"
  case "$phase_name" in
    plan|tasks|review) ;;
    *) return 0 ;;
  esac
  command -v tmux >/dev/null 2>&1 || return 0
  [[ -n "${TMUX:-}" ]] || return 0
  local layout
  layout="$(flowai_cfg_layout)"

  local label="Phase"
  case "$phase_name" in
    plan)   label="Plan" ;;
    tasks)  label="Tasks" ;;
    review) label="Review (QA)" ;;
  esac

  if [[ "$layout" == "dashboard" ]]; then
    local pane_id="${TMUX_PANE:-}"
    [[ -n "$pane_id" ]] || return 0
    log_info "✅ ${label} complete — closing this pane shortly (dashboard layout). Master + Implement stay open."
    ( sleep 0.5; tmux kill-pane -t "$pane_id" 2>/dev/null || true ) &
    return 0
  fi

  if [[ "$layout" == "tabs" ]]; then
    local sess win
    sess="$(tmux display-message -p '#S' 2>/dev/null)" || return 0
    win="$(tmux display-message -p '#I' 2>/dev/null)" || return 0
    log_info "✅ ${label} complete — closing this window shortly (tabs layout). Master + Implement stay open."
    ( sleep 0.5; tmux kill-window -t "${sess}:${win}" 2>/dev/null || true ) &
    return 0
  fi

  return 0
}

# Backward-compatible name (Plan-only callers historically).
flowai_phase_schedule_close_plan_ui() {
  flowai_phase_schedule_close_phase_ui "$1"
}

# Print the universal artifact boundary rule for a given phase.
# This is the single source of truth for phase artifact ownership.
# Usage: flowai_phase_artifact_boundary <phase_name>
flowai_phase_artifact_boundary() {
  local phase_name="$1"
  cat <<BOUNDARY

ARTIFACT BOUNDARY (MANDATORY — applies to ALL phases and roles):
You are the '${phase_name}' phase.
ALLOWED: You may ONLY write to the OUTPUT FILE specified above.
PROHIBITED: Do NOT create any other files. Specifically:
  - Do NOT create *_REVIEW.md, *_PLAN.md, *_SUMMARY.md, *_REPORT.md or similar
  - Do NOT create files that belong to other phases
  - If your output is verbal (e.g., review findings), say it in the conversation
The pipeline artifact ownership is:
  spec/master → spec.md | plan → plan.md | tasks → tasks.md
  impl → source code | review → verbal only (no files)
Violating this rule breaks the pipeline for all downstream agents.
BOUNDARY
}

# Compose the injected prompt file: role content + phase directive + artifact boundary.
# Prints the path of the written file.
# Usage: flowai_phase_write_prompt <phase_name> <role_file> <directive>
flowai_phase_write_prompt() {
  local phase_name="$1"
  local role_file="$2"
  local directive="$3"
  local out="${FLOWAI_DIR}/launch/${phase_name}_prompt.md"
  mkdir -p "${FLOWAI_DIR}/launch"
  { cat "$role_file"; printf '\n%s\n' "$directive"; flowai_phase_artifact_boundary "$phase_name"; } > "$out"
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
  # Focus the tmux pane/window on this phase so the user sees progress
  flowai_phase_focus "$phase_name" 2>/dev/null || true

  while true; do
    log_info "⏳ $artifact_label: AI agent is working (stream output appears below as the tool runs)..."
    flowai_ai_run "$phase_name" "$prompt_file" "false"
    log_success "✅ $artifact_label: AI agent finished. Verifying output..."
    log_info "📄 Expected artifact: $artifact_file"
    local rc=0
    flowai_phase_verify_artifact "$artifact_file" "$artifact_label" "$signal_name" || rc=$?
    
    if [[ "$rc" -eq 0 ]]; then
      flowai_event_emit "$phase_name" "phase_complete" "Approved and signalled"
      flowai_phase_schedule_close_phase_ui "$phase_name"
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
    master) role_name="master" ;;
    *)      role_name="$(flowai_cfg_pipeline_role "$phase" "backend-engineer")" ;;
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

# Switch tmux focus to the pane or window running a specific phase.
# Supports both dashboard layout (panes) and tabs layout (windows).
# Silently no-ops if tmux is not available or the phase pane is not found.
# Usage: flowai_phase_focus <phase_name>
flowai_phase_focus() {
  local phase="$1"
  command -v tmux >/dev/null 2>&1 || return 0
  [[ -n "${TMUX:-}" ]] || return 0

  local session
  session="$(tmux display-message -p '#S' 2>/dev/null)" || return 0

  # Try tabs layout first: look for a window named after the phase
  if tmux select-window -t "${session}:${phase}" 2>/dev/null; then
    return 0
  fi

  # Dashboard layout: scan pane titles for the phase name
  local pane_id
  pane_id="$(tmux list-panes -t "${session}" -F '#{pane_id} #{pane_title}' 2>/dev/null \
    | grep -i "$phase" | head -1 | awk '{print $1}')" || true
  if [[ -n "$pane_id" ]]; then
    tmux select-pane -t "$pane_id" 2>/dev/null || true
  fi
}
