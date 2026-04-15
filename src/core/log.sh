#!/usr/bin/env bash
# Core logging and output formatting using ANSI codes
# shellcheck shell=bash

# ANSI-C quoting ($'...') — required so ESC bytes are real (bash 3.2 does not treat \033 as octal inside "...").
BOLD=$'\033[1m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
RESET=$'\033[0m'

# Strip CSI/OSC sequences from strings before printing (Master status line, etc.).
# Prevents leaked terminal responses (e.g. OSC 11 color query) from polluting output when
# redraw (\r) races with tool subprocesses writing to the same tty.
flowai_sanitize_display_text() {
  local s="$1"
  [[ -n "$s" ]] || { printf ''; return 0; }
  if command -v perl >/dev/null 2>&1; then
    printf '%s' "$s" | LC_ALL=C perl -pe 's/\e\[[0-9:;?]*[A-Za-z]//g; s/\e\][^\a\e]*(\a|\e\\)//g'
    return 0
  fi
  printf '%s' "$s" | LC_ALL=C sed \
    -e $'s/\033\[[0-9:;?]*[A-Za-z]//g' \
    -e $'s/\033\][^\033\x07]*[\x07]//g' \
    -e $'s/\033\][^\033]*\033\\\\//g'
}

# FLOWAI_PLAIN_TERMINAL=1 — disable carriage-return / erase-line redraws (pipeline line, wait spinner).
# Without this, tmux/Terminal scrollback often shows mangled escape sequences after long sessions.
flowai_terminal_plain_enabled() {
  [[ "${FLOWAI_PLAIN_TERMINAL:-0}" == "1" ]]
}

log_info() {
    printf "${CYAN}ℹ ${BOLD}%s${RESET}\n" "$1"
}

log_success() {
    printf "${GREEN}✓ ${BOLD}%s${RESET}\n" "$1"
}

log_warn() {
    printf "${YELLOW}⚠ ${BOLD}%s${RESET}\n" "$1"
}

log_error() {
    printf "${RED}✗ ${BOLD}%s${RESET}\n" "$1" >&2
}

# Terminal width for carriage-return redraws. A fixed 120-column pad wraps on
# narrow tmux panes, so Master’s poll loop looked like “blank lines every few seconds.”
_flowai_terminal_width() {
  local w="${COLUMNS:-}"
  if [[ -z "$w" ]] || [[ ! "$w" =~ ^[0-9]+$ ]] || [[ "$w" -lt 1 ]]; then
    w="$(tput cols 2>/dev/null)" || w=80
  fi
  if [[ ! "$w" =~ ^[0-9]+$ ]] || [[ "$w" -lt 1 ]]; then
    w=80
  fi
  [[ "$w" -gt 200 ]] && w=200
  [[ "$w" -lt 16 ]] && w=80
  printf '%s' "$w"
}

# Overwrite the current line with space-padding (scrollback-safe).
# Uses spaces instead of CSI erase (\033[K / \033[2K) to avoid garbled
# ^[[K noise in tmux scrollback buffers.
flowai_overwrite_line() {
  local w
  w="$(_flowai_terminal_width)"
  printf '\r%*s\r%s' "$w" '' "$1"
}

flowai_clear_line() {
  local w
  w="$(_flowai_terminal_width)"
  printf '\r%*s\r' "$w" ''
}

log_header() {
    printf '\n%b%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' "$BOLD" "$CYAN" "$RESET"
    printf " %b%s%b\n" "$BOLD" "$1" "$RESET"
    printf '%b%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n\n' "$BOLD" "$CYAN" "$RESET"
}

# ─── Spinner — reusable braille-dot animation for polling loops ───────────────
# Smooth circular animation; each call to flowai_spinner_frame returns the next
# character. Use with flowai_overwrite_line for single-line progress indicators.
if [[ -z "${FLOWAI_SPINNER_FRAMES+x}" ]]; then
  readonly FLOWAI_SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
fi
FLOWAI_SPINNER_TICK=0

# Print the next spinner frame character (advances the global tick).
flowai_spinner_frame() {
  local frame="${FLOWAI_SPINNER_FRAMES[$(( FLOWAI_SPINNER_TICK % ${#FLOWAI_SPINNER_FRAMES[@]} ))]}"
  FLOWAI_SPINNER_TICK=$(( FLOWAI_SPINNER_TICK + 1 ))
  printf '%s' "$frame"
}
