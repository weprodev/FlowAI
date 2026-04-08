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

log_header() {
    printf '\n%b%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' "$BOLD" "$CYAN" "$RESET"
    printf " %b%s%b\n" "$BOLD" "$1" "$RESET"
    printf '%b%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n\n' "$BOLD" "$CYAN" "$RESET"
}
