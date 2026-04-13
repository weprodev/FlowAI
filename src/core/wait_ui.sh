#!/usr/bin/env bash
# Single-line wait progress for TTY — only the most upstream active waiter draws.
# shellcheck shell=bash

# Rank scale (lower = earlier in pipeline = wins the wait UI when several panes block).
readonly FLOWAI_WAIT_UI_RANK_PLAN=10
readonly FLOWAI_WAIT_UI_RANK_PLAN_REVISION=11
readonly FLOWAI_WAIT_UI_RANK_TASKS=20
readonly FLOWAI_WAIT_UI_RANK_TASKS_REVISION=21
# Referenced from src/phases/tasks.sh (poll for Master); not used inside this file.
# shellcheck disable=SC2034
readonly FLOWAI_WAIT_UI_RANK_TASKS_MASTER=22
readonly FLOWAI_WAIT_UI_RANK_IMPLEMENT=30
readonly FLOWAI_WAIT_UI_RANK_REVIEW=40
readonly FLOWAI_WAIT_UI_RANK_UNKNOWN=99

# Map phase label (2nd arg to flowai_phase_wait_for) to rank.
flowai_wait_ui_resolve_rank() {
  local label="$1"
  case "$label" in
    "Plan Phase") printf '%s' "$FLOWAI_WAIT_UI_RANK_PLAN" ;;
    "Tasks Phase") printf '%s' "$FLOWAI_WAIT_UI_RANK_TASKS" ;;
    "Implement Phase") printf '%s' "$FLOWAI_WAIT_UI_RANK_IMPLEMENT" ;;
    "Review Phase") printf '%s' "$FLOWAI_WAIT_UI_RANK_REVIEW" ;;
    *" revision"|*" Revision")
      case "$label" in
        *[Pp]lan*) printf '%s' "$FLOWAI_WAIT_UI_RANK_PLAN_REVISION" ;;
        *[Tt]asks*) printf '%s' "$FLOWAI_WAIT_UI_RANK_TASKS_REVISION" ;;
        *) printf '%s' 24 ;;
      esac
      ;;
    *) printf '%s' "$FLOWAI_WAIT_UI_RANK_UNKNOWN" ;;
  esac
}

_flowai_wait_ui_pid_alive() {
  kill -0 "$1" 2>/dev/null
}

# Portable mutex (mkdir); avoids flock (not on all macOS installs).
_flowai_wait_ui_spin_lock() {
  # Named without a leading dot so external tools scanning .flowai/ do not choke on ENOENT noise.
  local d="${SIGNALS_DIR}/flowai_wait_ui_spinlock"
  local n=0
  mkdir -p "$SIGNALS_DIR" 2>/dev/null || true
  while ! mkdir "$d" 2>/dev/null; do
    sleep 0.05
    n=$((n + 1))
    if [[ "$n" -gt 400 ]]; then
      return 1
    fi
  done
  return 0
}

_flowai_wait_ui_spin_unlock() {
  rmdir "${SIGNALS_DIR}/flowai_wait_ui_spinlock" 2>/dev/null || true
}

# Returns 0 if this process may draw the wait line; 1 if another waiter owns it or UI is disabled.
flowai_wait_ui_claim_or_skip() {
  local my_rank="$1"
  local my_pid=$$

  if [[ "${FLOWAI_TESTING:-0}" == "1" ]] || [[ ! -t 1 ]]; then
    return 1
  fi
  # Keep in sync with flowai_terminal_plain_enabled in log.sh (no log.sh dependency here).
  if [[ "${FLOWAI_PLAIN_TERMINAL:-0}" == "1" ]]; then
    return 1
  fi

  local owner="${SIGNALS_DIR}/.wait_ui_owner"
  _flowai_wait_ui_spin_lock || return 1

  local cur_rank="" cur_pid=""
  if [[ -f "$owner" ]]; then
    read -r cur_rank cur_pid _ <"$owner" || true
    if [[ -n "${cur_pid:-}" ]] && _flowai_wait_ui_pid_alive "$cur_pid"; then
      if [[ "$my_pid" -eq "$cur_pid" ]]; then
        _flowai_wait_ui_spin_unlock
        return 0
      fi
      if [[ -n "$cur_rank" ]] && [[ "$my_rank" -lt "$cur_rank" ]]; then
        printf '%s %s\n' "$my_rank" "$my_pid" >"$owner"
        _flowai_wait_ui_spin_unlock
        return 0
      fi
      if [[ -n "$cur_rank" ]] && [[ "$my_rank" -gt "$cur_rank" ]]; then
        _flowai_wait_ui_spin_unlock
        return 1
      fi
      _flowai_wait_ui_spin_unlock
      return 1
    fi
    rm -f "$owner"
  fi

  printf '%s %s\n' "$my_rank" "$my_pid" >"$owner"
  _flowai_wait_ui_spin_unlock
  return 0
}

flowai_wait_ui_release_if_owner() {
  local my_rank="$1"
  local my_pid=$$

  if [[ "${FLOWAI_TESTING:-0}" == "1" ]] || [[ ! -t 1 ]] || [[ "${FLOWAI_PLAIN_TERMINAL:-0}" == "1" ]]; then
    return 0
  fi

  local owner="${SIGNALS_DIR}/.wait_ui_owner"
  _flowai_wait_ui_spin_lock || return 0

  if [[ -f "$owner" ]]; then
    local cur_rank="" cur_pid=""
    read -r cur_rank cur_pid _ <"$owner" || true
    if [[ "$cur_pid" == "$my_pid" ]] && [[ "$cur_rank" == "$my_rank" ]]; then
      rm -f "$owner"
    fi
  fi
  _flowai_wait_ui_spin_unlock
}

# Args: elapsed_sec, step_sec (sleep interval in caller), short_label
#
# Overwrite strategy: \r + space-padding instead of \r\033[K (CSI erase).
# tmux scrollback buffers capture every CSI sequence, so hundreds of \033[K
# writes accumulate as garbled ^[[K / ^[[B noise when the user scrolls back.
# Space-padding is invisible in scrollback and avoids the problem entirely.
flowai_wait_ui_pulse_line() {
  local elapsed="$1"
  local step="${2:-2}"
  local short_label="$3"
  local c
  case $((elapsed / step % 4)) in
    0) c='|' ;;
    1) c='/' ;;
    2) c='-' ;;
    3) c="\\" ;;
  esac
  # Build the visible text, then pad to 80 chars to overwrite any previous content.
  local text
  text="$(printf '%s%s  %s · %ds%s' "$YELLOW" "$c" "$short_label" "$elapsed" "$RESET")"
  printf '\r%-80s\r%s' '' "$text"
}

flowai_wait_ui_clear_line() {
  if [[ "${FLOWAI_TESTING:-0}" == "1" ]] || [[ ! -t 1 ]] || [[ "${FLOWAI_PLAIN_TERMINAL:-0}" == "1" ]]; then
    return 0
  fi
  printf '\r%-80s\r' ''
}
