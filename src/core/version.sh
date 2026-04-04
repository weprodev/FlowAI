#!/usr/bin/env bash
# Install identity — read VERSION from repo root (FLOWAI_HOME).
# shellcheck shell=bash

flowai_version_read() {
  local vfile="${FLOWAI_HOME}/VERSION"
  if [[ -f "$vfile" ]]; then
    head -n1 "$vfile" | tr -d '\r'
  else
    printf '%s\n' "unknown"
  fi
}

flowai_version_print() {
  printf 'FlowAI %s\n' "$(flowai_version_read)"
}
