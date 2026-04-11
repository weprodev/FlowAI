#!/usr/bin/env bash
# macOS-specific platform implementations.
# shellcheck shell=bash

flowai_os_clipboard_copy_darwin() {
  local text="$1"
  if command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$text" | pbcopy 2>/dev/null || true
    return 0
  fi
  return 1
}

flowai_os_open_path_darwin() {
  local path="$1"
  if command -v open >/dev/null 2>&1; then
    open "$path" 2>/dev/null || true
  fi
}

flowai_os_install_hint_darwin() {
  local pkg="$1"
  printf 'brew install %s' "$pkg"
}

flowai_os_pkg_install_darwin() {
  local pkg="$1"
  if command -v brew >/dev/null 2>&1; then
    brew install "$pkg" 2>/dev/null
    return $?
  fi
  return 1
}

# Backward compat
agents_os_macos_clipboard_copy() { flowai_os_clipboard_copy_darwin "$@"; }
agents_os_macos_open_path()      { flowai_os_open_path_darwin "$@"; }
