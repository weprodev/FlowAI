#!/usr/bin/env bash
# Phase engine — signal coordination, feature dir resolution, human approval gates.
# shellcheck shell=bash

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/config.sh"
source "$FLOWAI_HOME/src/core/eventlog.sh"

export FLOWAI_DIR="${FLOWAI_DIR:-$PWD/.flowai}"
export SIGNALS_DIR="${FLOWAI_DIR}/signals"
export SPECS_DIR="${PWD}/specs"

# Emit a canonical pipeline error event (Master uses these for agent-agnostic recovery UX).
# Args: phase_id (e.g. plan, tasks, impl)  detail (human-readable)
flowai_phase_emit_error() {
  local phase_id="$1"
  local detail="${2:-}"
  flowai_event_emit "$phase_id" "error" "$detail"
}

# Diff summary for human approval UIs. Uses stdout capture only — never invokes
# Git's interactive pager (avoids less/(END) blocking tmux).
flowai_git_diff_stat_head() {
  git --no-pager diff --stat HEAD 2>/dev/null || true
}

# shellcheck source=src/core/wait_ui.sh
source "$FLOWAI_HOME/src/core/wait_ui.sh"
# shellcheck source=src/core/session.sh
source "$FLOWAI_HOME/src/core/session.sh"

if [[ ! -d "$FLOWAI_DIR" ]] || [[ ! -f "$FLOWAI_DIR/config.json" ]]; then
  log_error "Not a FlowAI project here — run: flowai init"
  exit 1
fi

# Check whether interactive gum selection menus should be used in this pane.
# Returns 1 (skip gum) when the current pane's tool cannot render gum choose
# (some tools capture terminal control sequences, breaking arrow-key navigation).
# Each tool plugin may declare flowai_tool_<name>_supports_gum() returning 1 to
# disable gum in its panes. If the function doesn't exist, gum is allowed.
_flowai_should_use_gum() {
  command -v gum >/dev/null 2>&1 || return 1
  local tool="${FLOWAI_PHASE_TOOL:-}"
  if [[ -n "$tool" ]] && declare -F "flowai_tool_${tool}_supports_gum" >/dev/null 2>&1; then
    "flowai_tool_${tool}_supports_gum" || return 1
  fi
  return 0
}

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

# Focus Master and close every other tmux pane (Implement, Review, Plan, …). Used right
# after final human approval so only Master shows the completion + next-step hints.
# No-op without tmux. Same skip rules as flowai_session_prompt_end.
flowai_session_close_non_master_panes() {
  if [[ "${FLOWAI_TESTING:-0}" == "1" ]]; then
    return 0
  fi
  if [[ "${FLOWAI_SESSION_END:-1}" == "0" ]]; then
    return 0
  fi
  command -v tmux >/dev/null 2>&1 || return 0
  [[ -n "${TMUX:-}" ]] || return 0

  log_info "Closing other agent panes (Implement, Review, …) — only Master stays open."
  flowai_phase_focus "master" 2>/dev/null || true
  flowai_tmux_kill_other_panes
}

# After pipeline success: wait for Enter on Master, then confirm quit → optional kill of the
# whole tmux session. Caller should run flowai_session_close_non_master_panes first (when in
# tmux) so Implement/Review panes are already gone before next-step hints + this wrap-up.
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
  log_info "Press Enter when you have finished reading the next steps above…"
  if [[ -r /dev/tty ]] && [[ -w /dev/tty ]]; then
    read -r _ </dev/tty || true
  else
    read -r _ || true
  fi

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
    local sess=""
    # Prefer the session we are actually in (avoids PWD / symlink mismatch vs flowai start).
    if [[ -n "${TMUX:-}" ]]; then
      sess="$(tmux display-message -p '#S' 2>/dev/null)" || true
    fi
    if [[ -z "$sess" ]] || ! tmux has-session -t "$sess" 2>/dev/null; then
      sess="$(flowai_resolve_tmux_session_name)"
    fi
    if tmux has-session -t "$sess" 2>/dev/null; then
      exec tmux kill-session -t "$sess"
    fi
    log_warn "Could not close the tmux session automatically (tried: ${sess:-unknown}). Run: flowai kill"
    # Do not `exit` here — that would skip master.sh teardown; return so the outer script can retry.
    return 0
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
  flowai_phase_resize_panes "$my_phase"
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

# Update status markers inside the approved artifact MD file.
# AI agents often write status lines like "**Specification Status:** DRAFT" or
# "**Status:** DRAFT". On human approval, patch these to APPROVED so the document
# reflects reality when read later.
# Args: target_file, phase_id
_flowai_phase_update_artifact_status() {
  local target_file="$1"
  local phase_id="$2"

  [[ -f "$target_file" ]] || return 0

  # Replace status markers: DRAFT → APPROVED (case-insensitive match for the value)
  if grep -qiE '\*\*.*Status:\*\*\s*(DRAFT|PENDING|IN.REVIEW)' "$target_file" 2>/dev/null; then
    sed -i.bak -E 's/(\*\*[^*]*Status:\*\*[[:space:]]*)(DRAFT|PENDING|IN.REVIEW)/\1APPROVED/gi' "$target_file"
    rm -f "${target_file}.bak"
  fi

  # Update "Next Step" lines that mention awaiting approval
  if grep -qiE '\*\*Next Step:\*\*.*[Aa]wait.*approval' "$target_file" 2>/dev/null; then
    local next_phase=""
    case "$phase_id" in
      spec) next_phase="Proceed to Plan phase" ;;
      plan) next_phase="Proceed to Tasks phase" ;;
      review) next_phase="Implementation complete" ;;
      *) next_phase="Approved — proceed to next phase" ;;
    esac
    sed -i.bak -E "s/(\*\*Next Step:\*\*).*/\1 ${next_phase}/" "$target_file"
    rm -f "${target_file}.bak"
  fi
}

# Print phase-specific context before the approval gate so the user knows
# exactly what they are approving. Inspired by spec-kit's approval patterns:
# show coverage metrics, change stats, and a clear "what approve means" line.
# Args: phase_id, target_file, [omit_git_stat]
# omit_git_stat=1 skips the git diff --stat block (caller already showed it).
_flowai_phase_approval_context() {
  local phase_id="$1"
  local target_file="$2"
  local omit_git_stat="${3:-0}"

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
      printf '  Artifact: %s\n' "$target_file"
      printf '\n'
      # Git diff summary (--no-pager: never invoke less; scrollback stays in tmux)
      if [[ "$omit_git_stat" != "1" ]]; then
        local diff_stat
        diff_stat="$(flowai_git_diff_stat_head)"
        if [[ -n "$diff_stat" ]]; then
          printf '  %sFiles changed:%s\n' "$BOLD" "$RESET"
          printf '%s\n' "$diff_stat" | while IFS= read -r line; do
            printf '    %s\n' "$line"
          done
          printf '\n'
        fi
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
#       [omit_git_stat] — if "1", skip git diff --stat in approval banner (already shown by caller).
# Returns: 0 = approved, 1 = retry agent, 2 = needs changes (reject).
flowai_phase_verify_artifact() {
  local target_file="$1"
  local artifact_label="$2"
  local phase_id="$3"
  local omit_git_stat="${4:-0}"

  while [[ ! -f "$target_file" ]]; do
    log_error "Required output not found: $target_file"

    local action=""
    if _flowai_should_use_gum; then
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
  _flowai_phase_approval_context "$phase_id" "$target_file" "$omit_git_stat"

  printf '\n'

  while true; do
    local decision=""
    if _flowai_should_use_gum; then
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
      local my_editor="${EDITOR:-vi}"
      if _flowai_should_use_gum; then
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
      _flowai_phase_update_artifact_status "$target_file" "$phase_id"
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

# Check if a phase pane is alive in tmux. Returns 0 if alive, 1 if dead/missing.
# Works for both dashboard (pane titles) and tabs (window names) layouts.
# Args: $1=phase_name (e.g. "impl", "review")
flowai_phase_is_pane_alive() {
  local phase="$1"
  command -v tmux >/dev/null 2>&1 || return 1
  [[ -n "${TMUX:-}" ]] || return 1

  local session
  session="$(tmux display-message -p '#S' 2>/dev/null)" || return 1

  # Tabs layout: check for a window named after the phase
  if tmux list-windows -t "$session" -F '#{window_name}' 2>/dev/null | grep -qx "$phase"; then
    return 0
  fi

  # Dashboard layout: scan pane titles for the phase name
  if tmux list-panes -t "${session}" -F '#{pane_title}' 2>/dev/null | grep -qi "$phase"; then
    return 0
  fi

  return 1
}

# Respawn a dead phase pane by creating a new tmux window/pane and launching
# the phase script. Uses the launcher scripts written by start.sh.
# Args: $1=phase_name (e.g. "impl", "review")
# Returns: 0 on success, 1 if respawn not possible.
flowai_phase_respawn() {
  local phase="$1"
  command -v tmux >/dev/null 2>&1 || return 1
  [[ -n "${TMUX:-}" ]] || return 1

  local session
  session="$(tmux display-message -p '#S' 2>/dev/null)" || return 1

  # Find the launcher script — start.sh writes these to FLOWAI_DIR/launch/
  local launcher=""
  for f in "${FLOWAI_DIR}/launch"/tmux_phase_*.sh; do
    [[ -f "$f" ]] || continue
    if grep -q "run ${phase}\$" "$f" 2>/dev/null || grep -q "run ${phase} " "$f" 2>/dev/null; then
      launcher="$f"
      break
    fi
  done

  if [[ -z "$launcher" ]]; then
    log_warn "Cannot respawn $phase — no launcher script found in ${FLOWAI_DIR}/launch/"
    return 1
  fi

  local layout
  layout="$(flowai_cfg_layout)"
  local phase_res
  phase_res="$(flowai_ai_resolve_tool_and_model_for_phase "$phase" 2>/dev/null || echo "unknown:unknown")"
  local phase_title="🤖 Phase: ${phase} [${phase_res%%:*}: ${phase_res#*:}]"

  if [[ "$layout" == "dashboard" ]]; then
    tmux split-window -t "${session}:0" -v
    local new_pane
    new_pane="$(tmux list-panes -t "${session}:0" -F '#{pane_id}' 2>/dev/null | tail -1)"
    tmux select-pane -t "$new_pane" -T "$phase_title"
    tmux send-keys -t "$new_pane" "bash '$launcher'" Enter
  else
    # Tabs layout: create a new window
    tmux new-window -t "${session}" -n "$phase"
    tmux set-window-option -t "${session}:${phase}" pane-border-status top 2>/dev/null || true
    tmux set-window-option -t "${session}:${phase}" pane-border-format " #[bold]#{pane_title}#[default] " 2>/dev/null || true
    tmux select-pane -t "${session}:${phase}" -T "$phase_title" 2>/dev/null || true
    tmux send-keys -t "${session}:${phase}" "bash '$launcher'" Enter
  fi

  log_info "Respawned $phase phase pane."
  flowai_event_emit "master" "phase_respawned" "Respawned dead $phase pane"
  return 0
}

# Print the universal artifact boundary rule for a given phase.
# This is the single source of truth for phase artifact ownership.
# Args: $1=phase_name  [$2=secondary_output — extra sentence appended to ALLOWED line]
# Usage: flowai_phase_artifact_boundary <phase_name>
# Usage: flowai_phase_artifact_boundary "review" "When blocking impl, you may ALSO write the rejection file."
flowai_phase_artifact_boundary() {
  local phase_name="$1"
  local secondary="${2:-}"

  local allowed_line="ALLOWED: You may ONLY write to the OUTPUT FILE specified above."
  if [[ -n "$secondary" ]]; then
    allowed_line="ALLOWED: You may write to the OUTPUT FILE specified above.
  ${secondary}"
  fi

  cat <<BOUNDARY

ARTIFACT BOUNDARY (MANDATORY — applies to ALL phases and roles):
You are the '${phase_name}' phase.
${allowed_line}
PROHIBITED: Do NOT create any other files. Specifically:
  - Do NOT create *_PLAN.md, *_SUMMARY.md, *_REPORT.md or similar
  - Do NOT create files that belong to other phases
The pipeline artifact ownership is:
  spec/master → spec.md | plan → plan.md | tasks → tasks.md
  impl → source code | review → review.md (+ optional rejection context when blocking)
Violating this rule breaks the pipeline for all downstream agents.
BOUNDARY
}

# Compose the injected prompt file: role content + phase directive + artifact boundary.
# Prints the path of the written file.
# Usage: flowai_phase_write_prompt <phase_name> <role_file> <directive> [secondary_boundary]
flowai_phase_write_prompt() {
  local phase_name="$1"
  local role_file="$2"
  local directive="$3"
  local secondary_boundary="${4:-}"
  local out="${FLOWAI_DIR}/launch/${phase_name}_prompt.md"
  mkdir -p "${FLOWAI_DIR}/launch"
  { cat "$role_file"; printf '\n%s\n' "$directive"; flowai_phase_artifact_boundary "$phase_name" "$secondary_boundary"; } > "$out"
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
    if [[ "${FLOWAI_AGENT_VERBOSE:-1}" == "1" ]]; then
      log_info "💡 Agent thinking is visible (FLOWAI_AGENT_VERBOSE=1). Set to 0 for quieter output."
    fi
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

  flowai_phase_resize_panes "$phase"
}

# Determine whether a pipeline phase is actively working (not waiting/completed).
# A phase is active when its upstream signal exists but its own completion signal does not.
# Args: phase_name (plan|tasks|impl|review)
# Returns: 0 if active, 1 if waiting or completed.
_flowai_phase_is_active() {
  local phase="$1"
  local upstream="" own=""
  case "$phase" in
    plan)   upstream="spec.ready";                   own="plan.ready" ;;
    tasks)  upstream="plan.ready";                   own="tasks.master_approved.ready" ;;
    impl)   upstream="tasks.master_approved.ready";  own="impl.code_complete.ready" ;;
    review) upstream="impl.code_complete.ready";     own="review.ready" ;;
    *)      return 1 ;;
  esac
  [[ -f "$SIGNALS_DIR/$upstream" ]] && [[ ! -f "$SIGNALS_DIR/$own" ]]
}

# Extract the phase name from a tmux pane title like "🤖 Phase: plan [gemini: ...]".
# Prints the phase name (plan, tasks, impl, review) or empty if not a phase pane.
_flowai_phase_name_from_title() {
  local title="$1"
  printf '%s' "$title" | sed -n 's/.*Phase:[[:space:]]*\([a-z]*\).*/\1/p'
}

# Resize tmux panes in dashboard layout.
# - Only touches pipeline phase panes (titles containing "Phase:") — never shrinks Master.
# - Detects which phases are actively working vs waiting on upstream signals.
# - Active phases get maximised; waiting/idle phases get minimised.
# - When 2+ phases are active simultaneously (e.g. impl + review): equal height for each.
# - Set FLOWAI_DASHBOARD_MAXIMIZE_FOCUS=1 to ignore signal detection and always
#   maximise only the caller's focused phase (legacy behaviour).
# No-ops gracefully in tabs layout, non-tmux, or FLOWAI_TESTING.
flowai_phase_resize_panes() {
  local active_phase="$1"
  command -v tmux >/dev/null 2>&1 || return 0
  [[ -n "${TMUX:-}" ]] || return 0
  [[ "${FLOWAI_TESTING:-0}" != "1" ]] || return 0

  local layout
  layout="$(flowai_cfg_layout)"
  [[ "$layout" == "dashboard" ]] || return 0

  local session
  session="$(tmux display-message -p '#S' 2>/dev/null)" || return 0

  local total_height
  total_height="$(tmux display-message -t "${session}:0" -p '#{window_height}' 2>/dev/null)" || return 0

  local pane_count
  pane_count="$(tmux list-panes -t "${session}:0" -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$pane_count" -gt 1 ]] || return 0

  local min_height="${FLOWAI_PANE_MIN_HEIGHT:-3}"

  # Collect pipeline phase panes (Plan/Tasks/Implement/Review) — not Master.
  local -a phase_ids=()
  local -a phase_names=()
  local _pid _ptitle _pname
  while IFS=$'\t' read -r _pid _ptitle; do
    _pname="$(_flowai_phase_name_from_title "$_ptitle")"
    if [[ -n "$_pname" ]]; then
      phase_ids+=("$_pid")
      phase_names+=("$_pname")
    fi
  done < <(tmux list-panes -t "${session}:0" -F '#{pane_id}	#{pane_title}' 2>/dev/null)

  local n_phase=${#phase_ids[@]}
  [[ "$n_phase" -ge 1 ]] || return 0

  # Legacy override: FLOWAI_DASHBOARD_MAXIMIZE_FOCUS=1 skips signal detection
  # and always maximises only the caller's focused phase.
  if [[ "${FLOWAI_DASHBOARD_MAXIMIZE_FOCUS:-0}" == "1" ]]; then
    local active_pane_id=""
    for _pid in "${phase_ids[@]}"; do
      _ptitle="$(tmux display-message -t "$_pid" -p '#{pane_title}' 2>/dev/null)" || true
      if printf '%s' "$_ptitle" | grep -qi "$active_phase"; then
        active_pane_id="$_pid"
        break
      fi
    done
    [[ -n "$active_pane_id" ]] || active_pane_id="${phase_ids[0]}"

    local k=$(( n_phase - 1 ))
    local stack_borders=$(( n_phase > 1 ? n_phase - 1 : 0 ))
    local active_height=$(( total_height - k * min_height - stack_borders ))
    [[ "$active_height" -lt "$min_height" ]] && active_height="$min_height"
    for _pid in "${phase_ids[@]}"; do
      if [[ "$_pid" != "$active_pane_id" ]]; then
        tmux resize-pane -t "$_pid" -y "$min_height" 2>/dev/null || true
      fi
    done
    tmux resize-pane -t "$active_pane_id" -y "$active_height" 2>/dev/null || true
    return 0
  fi

  # Default: signal-based active/waiting classification.
  # Active = upstream signal exists AND own completion signal absent.
  local -a active_pids=()
  local -a waiting_pids=()
  local i
  for (( i = 0; i < n_phase; i++ )); do
    if _flowai_phase_is_active "${phase_names[$i]}"; then
      active_pids+=("${phase_ids[$i]}")
    else
      waiting_pids+=("${phase_ids[$i]}")
    fi
  done

  # Fallback: if no phase detected as active, treat the focused phase as active.
  if [[ ${#active_pids[@]} -eq 0 ]]; then
    for (( i = 0; i < n_phase; i++ )); do
      if [[ "${phase_names[$i]}" == "$active_phase" ]]; then
        active_pids+=("${phase_ids[$i]}")
      else
        waiting_pids+=("${phase_ids[$i]}")
      fi
    done
    # Still nothing? Equal distribution.
    if [[ ${#active_pids[@]} -eq 0 ]]; then
      active_pids=("${phase_ids[@]}")
      waiting_pids=()
    fi
  fi

  local n_active=${#active_pids[@]}
  local n_waiting=${#waiting_pids[@]}

  # Calculate height: waiting panes get min_height, active panes share the rest equally.
  local borders=$(( n_phase - 1 ))
  local waiting_total=$(( n_waiting * min_height ))
  local active_space=$(( total_height - borders - waiting_total ))
  local each_active_h=$(( active_space / n_active ))
  [[ "$each_active_h" -lt "$min_height" ]] && each_active_h="$min_height"

  # Apply sizes: waiting panes first (shrink), then active panes (expand).
  for _pid in "${waiting_pids[@]}"; do
    tmux resize-pane -t "$_pid" -y "$min_height" 2>/dev/null || true
  done
  for _pid in "${active_pids[@]}"; do
    tmux resize-pane -t "$_pid" -y "$each_active_h" 2>/dev/null || true
  done
}
