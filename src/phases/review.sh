#!/usr/bin/env bash
# FlowAI — Review / QA phase
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/ai.sh"
source "$FLOWAI_HOME/src/core/phase.sh"

flowai_phase_wait_for "impl.code_complete" "Review Phase"

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
readonly REVIEW_DOC="$FEATURE_DIR/review.md"

DIRECTIVE="IMPORTANT PIPELINE DIRECTIVE:
You are assigned to Phase: Review (QA / quality).
Your WORKING DIRECTORY is: $PWD

OUTPUT FILE (mandatory): Write your full QA report to:
  $REVIEW_DOC

IMPORTANT: review.md is the ONLY file you create. Do NOT create separate report files
(e.g. ARCHITECTURE_REVIEW.md, CODE_QUALITY_REVIEW.md, REMEDIATION_PLAN.md).
Use sections within review.md for different review aspects.

Keep the report clean, short, and human-readable. Use references to code locations
where needed but avoid excessive detail. Include: summary verdict, checks vs
acceptance criteria, test/lint results, risks, and concrete recommendations.
The human approves using the menu in the terminal but opens this file in the
editor to read the full write-up (tmux output alone is not enough).

CONTEXT — read ALL upstream artifacts to perform a thorough review:
  $FEATURE_DIR/spec.md    (original requirements and acceptance criteria)
  $FEATURE_DIR/plan.md    (architecture decisions and approach)
  $FEATURE_DIR/tasks.md   (implementation checklist — verify all tasks completed)

Review the implementation against the spec's acceptance criteria and the plan's
architecture decisions. Run checks (tests, linters) as appropriate.

If you find blocking issues, ALSO write a structured rejection summary to:
  $REJECTION_CONTEXT_FILE

Format your rejection file as:
  ## Failed Tasks
  - [ ] Task description — reason for failure
  ## Test Failures
  - file:line — error message
  ## Required Fixes
  - Description of what needs to change

That file is provided to the Implement agent on re-run. Keep $REVIEW_DOC as the
complete human-readable QA record either way.

Summarize in chat only after the file is written."

INJECTED_PROMPT="$(flowai_phase_write_prompt "review" "$ROLE_FILE" "$DIRECTIVE" \
  "When blocking implementation, you may ALSO write the structured rejection file ($REJECTION_CONTEXT_FILE) for the Implement agent.")"
export INJECTED_PROMPT

log_info "Booting Review phase..."
log_info "QA scope: the whole implementation in this repo (git diff, tests/audit, spec + plan + tasks cross-check) — see your role and the directive above."
log_info "Primary artifact for this phase: review.md (human opens it from the approval menu)."

# Pre-create review.md so the agent can read/edit it without 'File not found'
if [[ ! -f "$REVIEW_DOC" ]]; then
  cat > "$REVIEW_DOC" <<'REVIEWTPL'
# QA Review

<!-- This file is the primary output of the Review phase. -->
<!-- The Review agent will replace this template with the full QA report. -->
REVIEWTPL
fi

flowai_phase_run_loop "review" "$INJECTED_PROMPT" "$REVIEW_DOC" "Implementation QA" "review"
