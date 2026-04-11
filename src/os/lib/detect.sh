#!/usr/bin/env bash
# FlowAI — OS detection and unified platform API.
#
# Detects the current OS and sources the correct platform module.
# Provides a unified API so callers never need to check the OS themselves.
#
# Usage:
#   source "$FLOWAI_HOME/src/os/lib/detect.sh"
#   flowai_os_id                    # → darwin | linux | windows
#   flowai_os_clipboard_copy "text" # works on any OS
#   flowai_os_open_path "./file"    # opens in default app
#   flowai_os_install_hint "jq"     # → "brew install jq" / "apt install jq" / "choco install jq"
#   flowai_os_pkg_install "jq"      # attempts auto-install (best effort)
#
# shellcheck shell=bash

# ── OS Detection ─────────────────────────────────────────────────────────────

flowai_os_id() {
  case "$(uname -s 2>/dev/null)" in
    Darwin)              echo darwin ;;
    Linux)               echo linux ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *)                   echo unknown ;;
  esac
}

flowai_os_is_darwin()  { [[ "$(flowai_os_id)" == "darwin" ]]; }
flowai_os_is_linux()   { [[ "$(flowai_os_id)" == "linux" ]]; }
flowai_os_is_windows() { [[ "$(flowai_os_id)" == "windows" ]]; }

# Cache the OS ID (called once at source time)
FLOWAI_OS="$(flowai_os_id)"
export FLOWAI_OS

# ── Backward compat aliases ──────────────────────────────────────────────────
agents_os_id()         { flowai_os_id; }
agents_os_is_darwin()  { flowai_os_is_darwin; }
agents_os_is_linux()   { flowai_os_is_linux; }
agents_os_is_windows() { flowai_os_is_windows; }
