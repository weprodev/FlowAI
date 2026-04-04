#!/usr/bin/env bash
# Install FlowAI to /usr/local/flowai and symlink flowai into PATH.
# Usage: from the FlowAI repo root — ./install.sh
# shellcheck shell=bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOWAI_SRC="$(CDPATH="" cd "$SCRIPT_DIR" && pwd)"

BOLD="\033[1m"
GREEN="\033[32m"
CYAN="\033[36m"
YELLOW="\033[33m"
RESET="\033[0m"

echo -e "${BOLD}${CYAN}Installing FlowAI...${RESET}"

INSTALL_DIR="/usr/local/flowai"
BIN_DIR="/usr/local/bin"

if [[ "$EUID" -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

if [[ ! -d "$FLOWAI_SRC/bin" ]] || [[ ! -f "$FLOWAI_SRC/bin/flowai" ]]; then
  echo -e "${YELLOW}Run this script from the FlowAI repository root (expected bin/flowai).${RESET}" >&2
  exit 1
fi

echo "Source: $FLOWAI_SRC"
echo "Target: $INSTALL_DIR"

$SUDO mkdir -p "$INSTALL_DIR"

if command -v rsync >/dev/null 2>&1; then
  $SUDO rsync -a --delete --exclude '.git' "$FLOWAI_SRC/" "$INSTALL_DIR/"
else
  $SUDO rm -rf "$INSTALL_DIR"
  $SUDO mkdir -p "$INSTALL_DIR"
  for item in bin src VERSION LICENSE README.md install.sh; do
    if [[ -e "$FLOWAI_SRC/$item" ]]; then
      $SUDO cp -R "$FLOWAI_SRC/$item" "$INSTALL_DIR/"
    fi
  done
fi

$SUDO chmod -R a+rX "$INSTALL_DIR"
$SUDO chmod +x "$INSTALL_DIR/bin/flowai"
$SUDO ln -sf "$INSTALL_DIR/bin/flowai" "$BIN_DIR/flowai"

echo -e "\n${BOLD}${GREEN}✅ FlowAI installed.${RESET}"
echo -e "Try: ${BOLD}flowai init${RESET} inside a git project, then ${BOLD}flowai start${RESET}."
