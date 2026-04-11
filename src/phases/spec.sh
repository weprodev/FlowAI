#!/usr/bin/env bash
# FlowAI — Spec artifact phase (usually driven by Master role content).
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/ai.sh"
source "$FLOWAI_HOME/src/core/phase.sh"

FEATURE_DIR="$(flowai_phase_resolve_feature_dir)"
if [[ -z "$FEATURE_DIR" ]]; then
  log_error "No feature directory under specs/. Create one (e.g. make specify / Spec Kit) or mkdir specs/<branch>."
  exit 1
fi

if [[ "${FLOWAI_TEST_SKIP_AI:-}" == "1" ]]; then
  log_info "FLOWAI_TEST_SKIP_AI=1 — skipping AI run (contract test)."
  exit 0
fi

ROLE_FILE="$(flowai_phase_resolve_role_prompt "spec")"
DIRECTIVE="IMPORTANT PIPELINE DIRECTIVE:
You are assigned to Phase: Specification.
Your WORKING DIRECTORY is: $PWD

OUTPUT FILE — you MUST write your artifact to this exact path:
  $FEATURE_DIR/spec.md

Complete your phase tasks as thoroughly as possible. When you finish, exit immediately."

INJECTED_PROMPT="$(flowai_phase_write_prompt "spec" "$ROLE_FILE" "$DIRECTIVE")"
export INJECTED_PROMPT

log_info "Booting Spec phase..."
flowai_phase_run_loop "spec" "$INJECTED_PROMPT" "$FEATURE_DIR/spec.md" "Specification" "spec"
