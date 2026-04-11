#!/usr/bin/env bash
# Lint the codebase using shellcheck

set -euo pipefail

CYAN=$'\033[36m'
YELLOW=$'\033[33m'
RESET=$'\033[0m'

if ! command -v shellcheck >/dev/null 2>&1; then
  printf "\n%b╭──────────────────────────────────────────────────────╮%b\n" "$YELLOW" "$RESET"
  printf "%b│ [!] WARNING: shellcheck not found in PATH            │%b\n" "$YELLOW" "$RESET"
  printf "%b│     Skipping linting! Run: brew install shellcheck   │%b\n" "$YELLOW" "$RESET"
  printf "%b╰──────────────────────────────────────────────────────╯%b\n\n" "$YELLOW" "$RESET"
  exit 0
fi

printf "%bRunning ShellCheck...%b\n" "$CYAN" "$RESET"

shopt -s nullglob
errors=0

for f in \
  bin/flowai \
  install.sh \
  src/commands/*.sh \
  src/phases/*.sh \
  src/core/*.sh \
  src/bootstrap/*.sh \
  tests/run.sh \
  tests/lib/*.sh \
  tests/suites/*.sh \
  tests/agent/*.sh \
  scripts/*.sh; \
do
  printf "  %bshellcheck%b %s\n" "$CYAN" "$RESET" "$f"
  if ! shellcheck -x "$f"; then
    errors=$((errors + 1))
  fi
done

if [[ "$errors" -gt 0 ]]; then
  exit 1
fi
