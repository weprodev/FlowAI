#!/usr/bin/env bash
# Windows-specific platform implementations (Git Bash / MSYS2 / Cygwin).
# shellcheck shell=bash

flowai_os_clipboard_copy_windows() {
  local text="$1"
  # clip.exe is available in Git Bash and MSYS2
  if command -v clip.exe >/dev/null 2>&1; then
    printf '%s' "$text" | clip.exe 2>/dev/null || true
    return 0
  fi
  # PowerShell fallback
  if command -v powershell.exe >/dev/null 2>&1; then
    printf '%s' "$text" | powershell.exe -Command 'Set-Clipboard -Value ([Console]::In.ReadToEnd())' 2>/dev/null || true
    return 0
  fi
  return 1
}

flowai_os_open_path_windows() {
  local path="$1"
  if command -v start >/dev/null 2>&1; then
    start "$path" 2>/dev/null || true
  elif command -v explorer.exe >/dev/null 2>&1; then
    explorer.exe "$path" 2>/dev/null || true
  fi
}

flowai_os_install_hint_windows() {
  local pkg="$1"
  if command -v choco >/dev/null 2>&1; then
    printf 'choco install %s' "$pkg"
  elif command -v scoop >/dev/null 2>&1; then
    printf 'scoop install %s' "$pkg"
  elif command -v winget.exe >/dev/null 2>&1; then
    printf 'winget install %s' "$pkg"
  else
    printf 'Install %s via Chocolatey, Scoop, or winget' "$pkg"
  fi
}

flowai_os_pkg_install_windows() {
  local pkg="$1"
  if command -v choco >/dev/null 2>&1; then
    choco install -y "$pkg" 2>/dev/null
    return $?
  elif command -v scoop >/dev/null 2>&1; then
    scoop install "$pkg" 2>/dev/null
    return $?
  fi
  return 1
}

# Backward compat
agents_os_windows_clipboard_copy() { flowai_os_clipboard_copy_windows "$@"; }
agents_os_windows_open_path()      { flowai_os_open_path_windows "$@"; }
