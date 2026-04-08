#!/usr/bin/env bash
# FlowAI — Review / QA phase
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/ai.sh"
source "$FLOWAI_HOME/src/core/phase.sh"

flowai_phase_wait_for "impl" "Review Phase"

FEATURE_DIR="$(flowai_phase_resolve_feature_dir)"
if [[ -z "$FEATURE_DIR" ]]; then
  log_error "No feature directory under specs/."
  exit 1
fi

if [[ "${FLOWAI_TEST_SKIP_AI:-}" == "1" ]]; then
  log_info "FLOWAI_TEST_SKIP_AI=1 — skipping AI run (contract test)."
  exit 0
fi

ROLE_FILE="$(flowai_phase_resolve_role_prompt "review")"
DIRECTIVE="IMPORTANT PIPELINE DIRECTIVE:
You are assigned to Phase: Review (QA / quality).
Your WORKING DIRECTORY is: $PWD

CONTEXT — read tasks and verify the codebase:
  $FEATURE_DIR/tasks.md

Run checks (tests, linters) as appropriate. Summarize findings or confirm clean."

INJECTED_PROMPT="$(flowai_phase_write_prompt "review" "$ROLE_FILE" "$DIRECTIVE")"
export INJECTED_PROMPT

log_info "Booting Review phase..."
flowai_phase_run_loop "review" "$INJECTED_PROMPT" "$FEATURE_DIR/tasks.md" "Review" "review"
