#!/usr/bin/env bash
# Stable tmux session name per repository path (avoids collisions when two projects share the same directory name).
# shellcheck shell=bash

flowai_session_hash() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$path" | shasum -a 256 | cut -c1-12
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$path" | sha256sum | cut -c1-12
  else
    printf '%s' "$path" | cksum | awk '{print $1}'
  fi
}

flowai_session_name() {
  local root="${1:-$PWD}"
  printf 'flowai-%s' "$(flowai_session_hash "$root")"
}

# Repository root used for tmux session names — must match `flowai start`, which uses
# `flowai_session_name "$PWD"` with $PWD at project init (FLOWAI_DIR="$PWD/.flowai").
# Using this instead of raw $PWD fixes teardown when the shell cwd drifted to a subdir.
flowai_repo_root_for_session() {
  local fd="${FLOWAI_DIR:-$PWD/.flowai}"
  fd="${fd%/}"
  case "$fd" in
    */.flowai) printf '%s' "${fd%/.flowai}" ;;
    *)         printf '%s' "${PWD:-.}" ;;
  esac
}

# Session name for kill/teardown: prefer pipeline.complete, else hash(repo root for session).
flowai_resolve_tmux_session_name() {
  local pc name
  pc="${FLOWAI_DIR:-$PWD/.flowai}/signals/pipeline.complete"
  name=""
  if [[ -f "$pc" ]] && [[ -s "$pc" ]]; then
    name="$(head -n 1 "$pc" 2>/dev/null | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  fi
  if [[ -n "$name" ]]; then
    printf '%s' "$name"
    return 0
  fi
  flowai_session_name "$(flowai_repo_root_for_session)"
}
