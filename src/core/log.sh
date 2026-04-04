#!/usr/bin/env bash
# Core logging and output formatting using ANSI codes
# shellcheck shell=bash

export BOLD="\033[1m"
export CYAN="\033[36m"
export GREEN="\033[32m"
export YELLOW="\033[33m"
export MAGENTA="\033[35m"
export RED="\033[31m"
export RESET="\033[0m"

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
    printf "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
    printf " ${BOLD}%s${RESET}\n" "$1"
    printf "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n\n"
}
