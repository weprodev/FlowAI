#!/usr/bin/env bash
# FlowAI — Plan phase
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/ai.sh"
source "$FLOWAI_HOME/src/core/phase.sh"

flowai_phase_wait_for "spec" "Plan Phase"

FEATURE_DIR="$(flowai_phase_resolve_feature_dir)"
if [[ -z "$FEATURE_DIR" ]]; then
  log_error "No feature directory under specs/."
  exit 1
fi

if [[ "${FLOWAI_TEST_SKIP_AI:-}" == "1" ]]; then
  log_info "FLOWAI_TEST_SKIP_AI=1 — skipping AI run (contract test)."
  exit 0
fi

ROLE_FILE="$(flowai_phase_resolve_role_prompt "plan")"
DIRECTIVE="IMPORTANT PIPELINE DIRECTIVE:
You are assigned to Phase: Plan (Architecture).
Your WORKING DIRECTORY is: $PWD

CONTEXT — read the following upstream artifact before starting:
  $FEATURE_DIR/spec.md

OUTPUT FILE — you MUST write your artifact to this exact path:
  $FEATURE_DIR/plan.md

POST-WRITE UX (required):
- When plan.md is written, tell the user the **absolute path** above.
- Tell them the FlowAI terminal will show an **approval menu** next (Approve / Needs changes / Review artifact).
- They must use that menu — you do not approve your own work.

Complete your phase tasks as thoroughly as possible. When you finish, exit immediately."

INJECTED_PROMPT="$(flowai_phase_write_prompt "plan" "$ROLE_FILE" "$DIRECTIVE")"
export INJECTED_PROMPT

log_info "Booting Plan phase..."
flowai_phase_run_loop "plan" "$INJECTED_PROMPT" "$FEATURE_DIR/plan.md" "Plan" "plan"
