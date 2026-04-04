#!/usr/bin/env bash
# FlowAI - Master Phase
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/ai.sh"
source "$FLOWAI_HOME/src/phases/lib.sh"

ROLE_FILE=""
if [[ -f "$FLOWAI_DIR/roles/master.md" ]]; then
    ROLE_FILE="$FLOWAI_DIR/roles/master.md"
else
    ROLE_FILE="$FLOWAI_HOME/src/roles/master.md"
fi

log_info "Booting Master Agent..."

# Master is interactive, does not wait for a previous phase
flowai_ai_run "master" "$ROLE_FILE" "true"
