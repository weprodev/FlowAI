#!/usr/bin/env bash
# FlowAI — kill tmux session for this repository
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/session.sh"

SESSION="$(flowai_session_name "$PWD")"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux kill-session -t "$SESSION"
  log_success "Session '$SESSION' killed."
else
  printf "${YELLOW}⚠ ${BOLD}No active session found for '%s'.${RESET}\n" "$SESSION" >&2
fi
