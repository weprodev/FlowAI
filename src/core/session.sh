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
