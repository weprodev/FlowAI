#!/usr/bin/env bash
# FlowAI seed stub for .specify/scripts/bash/common.sh
# This is a minimal replacement ensuring signal-protocol compatibility.
# Install GitHub Spec Kit for full functionality:
#   uvx --from git+https://github.com/github/spec-kit.git specify init . --ai claude --script sh
# shellcheck shell=bash

SPECIFY_ROOT="${SPECIFY_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}/.specify"
export SPECIFY_ROOT

specify_signal_ready() {
  local phase="${1:-unknown}"
  mkdir -p "$SPECIFY_ROOT/signals"
  touch "$SPECIFY_ROOT/signals/${phase}.ready"
}

specify_signal_clear() {
  local phase="${1:-unknown}"
  rm -f "$SPECIFY_ROOT/signals/${phase}.ready"
}

specify_signal_wait() {
  local phase="${1:-unknown}"
  local timeout="${2:-120}"
  local elapsed=0
  while [[ ! -f "$SPECIFY_ROOT/signals/${phase}.ready" ]]; do
    sleep 1
    elapsed=$((elapsed + 1))
    if [[ $elapsed -ge $timeout ]]; then
      echo "Timeout waiting for signal: ${phase}.ready" >&2
      return 1
    fi
  done
}
