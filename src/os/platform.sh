#!/usr/bin/env bash
# FlowAI — Unified platform API.
#
# Sources the correct OS-specific module and provides a single set of
# functions that work on any platform. Callers never need to know which
# OS they're on.
#
# Usage:
#   source "$FLOWAI_HOME/src/os/platform.sh"
#   flowai_os_clipboard_copy "text"
#   flowai_os_open_path "./report.md"
#   flowai_os_install_hint "jq"      # → "brew install jq" / "apt install jq" / etc.
#   flowai_os_pkg_install "jq"       # best-effort auto-install
#
# shellcheck shell=bash

_PLATFORM_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load detection
source "$_PLATFORM_DIR/lib/detect.sh"

# Load the OS-specific module
case "$FLOWAI_OS" in
  darwin)  source "$_PLATFORM_DIR/macos.sh" ;;
  linux)   source "$_PLATFORM_DIR/linux.sh" ;;
  windows) source "$_PLATFORM_DIR/windows.sh" ;;
esac

# ── Unified API ──────────────────────────────────────────────────────────────
# These dispatch to the OS-specific implementations loaded above.

flowai_os_clipboard_copy() {
  case "$FLOWAI_OS" in
    darwin)  flowai_os_clipboard_copy_darwin "$@" ;;
    linux)   flowai_os_clipboard_copy_linux "$@" ;;
    windows) flowai_os_clipboard_copy_windows "$@" ;;
    *)       return 1 ;;
  esac
}

flowai_os_open_path() {
  case "$FLOWAI_OS" in
    darwin)  flowai_os_open_path_darwin "$@" ;;
    linux)   flowai_os_open_path_linux "$@" ;;
    windows) flowai_os_open_path_windows "$@" ;;
    *)       return 1 ;;
  esac
}

flowai_os_install_hint() {
  case "$FLOWAI_OS" in
    darwin)  flowai_os_install_hint_darwin "$@" ;;
    linux)   flowai_os_install_hint_linux "$@" ;;
    windows) flowai_os_install_hint_windows "$@" ;;
    *)       printf 'Install %s using your package manager' "$1" ;;
  esac
}

flowai_os_pkg_install() {
  case "$FLOWAI_OS" in
    darwin)  flowai_os_pkg_install_darwin "$@" ;;
    linux)   flowai_os_pkg_install_linux "$@" ;;
    windows) flowai_os_pkg_install_windows "$@" ;;
    *)       return 1 ;;
  esac
}
