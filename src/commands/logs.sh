#!/usr/bin/env bash
# FlowAI — logs command
# Usage: flowai logs [phase]
# Fetch and read the output buffer for a specific background phase.
# shellcheck shell=bash

set -euo pipefail

# shellcheck source=../core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"
# shellcheck source=../core/session.sh
source "$FLOWAI_HOME/src/core/session.sh"

if ! command -v tmux >/dev/null 2>&1; then
  log_error "tmux is not installed. Logs are held in tmux buffers."
  exit 1
fi

SESSION="$(flowai_session_name "$PWD")"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  log_error "Session '$SESSION' is not running. Use: flowai start"
  exit 1
fi

phase="${1:-master}"

if ! tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -qx "$phase"; then
  log_error "Phase '$phase' is not currently running in session '$SESSION'."
  log_info "Available phase logs: $(tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | tr '\n' ' ')"
  exit 1
fi

if [[ -t 1 ]]; then
  # Interactive mode: use less, start at the bottom (+G), allow raw ansi (-R)
  # -X keeps content on screen after exit, -F quits if fits on one screen
  tmux capture-pane -t "${SESSION}:${phase}" -p -S - | less -RXF +G
else
  # Piped mode (CI): just dump the buffer
  tmux capture-pane -t "${SESSION}:${phase}" -p -S -
fi
