#!/usr/bin/env bash
# FlowAI — kill tmux session for this repository
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/session.sh"

SESSION="$(flowai_session_name "$PWD")"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  if [ -t 0 ] && [ "${FLOWAI_TESTING:-0}" != "1" ]; then
    if command -v gum >/dev/null 2>&1; then
      if ! gum confirm "Kill active FlowAI session '$SESSION'?"; then
        log_info "Cancelled."
        exit 0
      fi
    else
      read -r -p "Kill active FlowAI session '$SESSION'? [y/N]: " ans < /dev/tty || true
      if [[ ! "$ans" =~ ^[yY] ]]; then
        log_info "Cancelled."
        exit 0
      fi
    fi
  fi

  tmux kill-session -t "$SESSION"
  log_success "Session '$SESSION' killed."
else
  printf "${YELLOW}⚠ ${BOLD}No active session found for '%s'.${RESET}\n" "$SESSION" >&2
fi
