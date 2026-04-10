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
# Path injected into the AI directive below — the Review AI agent writes to this
# file when it finds issues. The Implement agent reads it on re-run.
readonly REJECTION_CONTEXT_FILE="$FLOWAI_DIR/signals/impl.rejection_context"

DIRECTIVE="IMPORTANT PIPELINE DIRECTIVE:
You are assigned to Phase: Review (QA / quality).
Your WORKING DIRECTORY is: $PWD

CONTEXT — read ALL upstream artifacts to perform a thorough review:
  $FEATURE_DIR/spec.md    (original requirements and acceptance criteria)
  $FEATURE_DIR/plan.md    (architecture decisions and approach)
  $FEATURE_DIR/tasks.md   (implementation checklist — verify all tasks completed)

Review the implementation against the spec's acceptance criteria and the plan's
architecture decisions. Run checks (tests, linters) as appropriate.

IMPORTANT: If you find issues, write a structured rejection summary to:
  $REJECTION_CONTEXT_FILE

Format your rejection file as:
  ## Failed Tasks
  - [ ] Task description — reason for failure
  ## Test Failures
  - file:line — error message
  ## Required Fixes
  - Description of what needs to change

This file will be provided to the Implement agent on re-run so it can focus
on ONLY the failing items instead of re-implementing everything.

Summarize findings or confirm clean."

INJECTED_PROMPT="$(flowai_phase_write_prompt "review" "$ROLE_FILE" "$DIRECTIVE")"
export INJECTED_PROMPT

log_info "Booting Review phase..."
flowai_phase_run_loop "review" "$INJECTED_PROMPT" "$FEATURE_DIR/tasks.md" "Review" "review"
