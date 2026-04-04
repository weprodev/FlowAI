#!/usr/bin/env bash
# OS detection — keep logic tiny; extend per-OS in scripts/os/<id>.sh without touching callers.
# shellcheck shell=bash

agents_os_id() {
  case "$(uname -s 2>/dev/null)" in
    Darwin) echo darwin ;;
    Linux) echo linux ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) echo unknown ;;
  esac
}

agents_os_is_darwin() { [[ "$(agents_os_id)" == "darwin" ]]; }
agents_os_is_linux() { [[ "$(agents_os_id)" == "linux" ]]; }
agents_os_is_windows() { [[ "$(agents_os_id)" == "windows" ]]; }
