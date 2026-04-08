#!/usr/bin/env bash
# FlowAI — Implement phase
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/ai.sh"
source "$FLOWAI_HOME/src/core/phase.sh"

flowai_phase_wait_for "tasks" "Implement Phase"

FEATURE_DIR="$(flowai_phase_resolve_feature_dir)"
if [[ -z "$FEATURE_DIR" ]]; then
  log_error "No feature directory under specs/."
  exit 1
fi

if [[ "${FLOWAI_TEST_SKIP_AI:-}" == "1" ]]; then
  log_info "FLOWAI_TEST_SKIP_AI=1 — skipping AI run (contract test)."
  exit 0
fi

ROLE_FILE="$(flowai_phase_resolve_role_prompt "impl")"
DIRECTIVE="IMPORTANT PIPELINE DIRECTIVE:
You are assigned to Phase: Implement (Code Writing).
Your WORKING DIRECTORY is: $PWD

CONTEXT — read the following upstream artifact before starting:
  $FEATURE_DIR/tasks.md

Implement the code required in tasks.md. Check off tasks as you complete them.
When blockers remain, document them and exit."

INJECTED_PROMPT="$(flowai_phase_write_prompt "impl" "$ROLE_FILE" "$DIRECTIVE")"
export INJECTED_PROMPT

log_info "Booting Implement phase..."
# impl uses tasks.md as the approval artifact (confirm all tasks are done)
flowai_phase_run_loop "impl" "$INJECTED_PROMPT" "$FEATURE_DIR/tasks.md" "Implementation" "impl"
