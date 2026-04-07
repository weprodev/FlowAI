#!/usr/bin/env bash
# FlowAI — project configuration helpers
# Usage: flowai config validate
# shellcheck shell=bash

set -euo pipefail

# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"

export FLOWAI_DIR="${FLOWAI_DIR:-$PWD/.flowai}"
export FLOWAI_CONFIG="$FLOWAI_DIR/config.json"

# shellcheck source=src/core/config-validate.sh
source "$FLOWAI_HOME/src/core/config-validate.sh"

subcmd="${1:-}"
shift || true

case "$subcmd" in
  validate)
    if ! flowai_config_validate_models; then
      printf '%s\n' "  Tip: use ids from flowai models list <tool>, or set FLOWAI_ALLOW_UNKNOWN_MODEL=1 to allow unlisted ids."
      exit 1
    fi
    log_success "Model configuration matches models-catalog.json"
    ;;
  -h|--help|help)
    printf '%s\n' "Usage: flowai config validate"
    printf '%s\n' "  Checks default_model, claude_default_model, master, and roles.* against models-catalog.json."
    printf '%s\n' "  FLOWAI_ALLOW_UNKNOWN_MODEL=1 — warn only, exit 0."
    ;;
  *)
    log_error "Unknown config subcommand: ${subcmd:-}"
    printf '%s\n' "Usage: flowai config validate"
    exit 1
    ;;
esac
