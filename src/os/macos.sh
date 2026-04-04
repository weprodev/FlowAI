#!/usr/bin/env bash
# macOS-specific helpers (clipboard, open, Homebrew assumptions).
# Other OS files mirror this surface area as we add real implementations.
# shellcheck shell=bash

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/detect.sh
source "$SCRIPT_DIR/lib/detect.sh"

agents_os_macos_clipboard_copy() {
  local text="$1"
  if agents_os_is_darwin && command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$text" | pbcopy 2>/dev/null || true
    return 0
  fi
  return 1
}

agents_os_macos_open_path() {
  local path="$1"
  if agents_os_is_darwin && command -v open >/dev/null 2>&1; then
    open "$path" 2>/dev/null || true
  fi
}
