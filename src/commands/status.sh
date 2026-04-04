#!/usr/bin/env bash
# FlowAI — show tmux session status for this repository
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/session.sh"

SESSION="$(flowai_session_name "$PWD")"

if ! command -v tmux >/dev/null 2>&1; then
  log_error "tmux is not installed."
  exit 1
fi

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  log_warn "Session '$SESSION' is not running."
  exit 0
fi

log_header "FlowAI session: $SESSION"
tmux list-windows -t "$SESSION"
