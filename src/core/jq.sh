#!/usr/bin/env bash
# FlowAI — jq discovery and PATH hardening
#
# conda/miniconda often ships jq 1.6, which reserves the binding name `label`.
# Graph code uses --arg lbl; older installs may still hit jq 1.6 quirks. Prefer
# Apple jq (/usr/bin/jq, jq 1.7.x) on macOS when the default `jq` is 1.6.
#
# Override: FLOWAI_JQ=/path/to/jq  — use this binary for all jq invocations
#           FLOWAI_JQ_SKIP_PATH_FIX=1 — do not modify PATH
#
# shellcheck shell=bash

# If set, must be an executable jq (used by tests or power users).
flowai_jq_cmd() {
  if [[ -n "${FLOWAI_JQ:-}" ]] && [[ -x "$FLOWAI_JQ" ]]; then
    printf '%s' "$FLOWAI_JQ"
    return 0
  fi
  command -v jq
}

# Prefer system jq on macOS when conda jq 1.6 shadows a newer /usr/bin/jq.
flowai_prefer_jq_path() {
  [[ "${FLOWAI_JQ_SKIP_PATH_FIX:-0}" == "1" ]] && return 0
  [[ -n "${FLOWAI_JQ:-}" ]] && return 0

  local os
  os="$(uname -s 2>/dev/null || true)"
  [[ "$os" == "Darwin" ]] || return 0
  [[ -x "/usr/bin/jq" ]] || return 0

  local current
  current="$(command -v jq 2>/dev/null || true)"
  [[ -n "$current" ]] || return 0
  [[ "$current" == "/usr/bin/jq" ]] && return 0

  local ver
  ver="$("$current" --version 2>/dev/null || true)"
  if [[ "$ver" == jq-1.6* ]]; then
    case ":${PATH:-}:" in
      *:/usr/bin:*) ;;
      *) export PATH="/usr/bin:${PATH}" ;;
    esac
    [[ "${FLOWAI_NO_JQ_PATH_HINT:-0}" == "1" ]] && return 0
    if command -v log_info >/dev/null 2>&1; then
      log_info "Using jq from /usr/bin (conda jq 1.6 is incompatible; PATH adjusted). Install: brew install jq" >&2
    else
      printf '%s\n' "FlowAI: using /usr/bin/jq — conda jq 1.6 is incompatible with graph tools." >&2
    fi
  fi
}
