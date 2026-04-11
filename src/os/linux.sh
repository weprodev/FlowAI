#!/usr/bin/env bash
# Linux-specific platform implementations.
# shellcheck shell=bash

flowai_os_clipboard_copy_linux() {
  local text="$1"
  # Wayland
  if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$text" | wl-copy 2>/dev/null || true
    return 0
  fi
  # X11
  if [[ -n "${DISPLAY:-}" ]] && command -v xclip >/dev/null 2>&1; then
    printf '%s' "$text" | xclip -selection clipboard 2>/dev/null || true
    return 0
  fi
  if [[ -n "${DISPLAY:-}" ]] && command -v xsel >/dev/null 2>&1; then
    printf '%s' "$text" | xsel --clipboard --input 2>/dev/null || true
    return 0
  fi
  return 1
}

flowai_os_open_path_linux() {
  local path="$1"
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$path" 2>/dev/null || true
  fi
}

flowai_os_install_hint_linux() {
  local pkg="$1"
  if command -v apt-get >/dev/null 2>&1; then
    printf 'sudo apt-get install %s' "$pkg"
  elif command -v dnf >/dev/null 2>&1; then
    printf 'sudo dnf install %s' "$pkg"
  elif command -v pacman >/dev/null 2>&1; then
    printf 'sudo pacman -S %s' "$pkg"
  elif command -v apk >/dev/null 2>&1; then
    printf 'apk add %s' "$pkg"
  else
    printf 'Install %s using your package manager' "$pkg"
  fi
}

flowai_os_pkg_install_linux() {
  local pkg="$1"
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get install -y -qq "$pkg" 2>/dev/null
    return $?
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y -q "$pkg" 2>/dev/null
    return $?
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --noconfirm "$pkg" 2>/dev/null
    return $?
  elif command -v apk >/dev/null 2>&1; then
    apk add "$pkg" 2>/dev/null
    return $?
  fi
  return 1
}

# Backward compat
agents_os_linux_clipboard_copy() { flowai_os_clipboard_copy_linux "$@"; }
agents_os_linux_open_path()      { flowai_os_open_path_linux "$@"; }
