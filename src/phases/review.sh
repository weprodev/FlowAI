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

ROLE_FILE="$(flowai_phase_resolve_role_prompt "review")"

export INJECTED_PROMPT="$FLOWAI_DIR/launch/review_prompt.md"
mkdir -p "$FLOWAI_DIR/launch"

cat <<EOF > "$INJECTED_PROMPT"
$(cat "$ROLE_FILE")

IMPORTANT PIPELINE DIRECTIVE:
You are assigned to Phase: Review (QA / quality).
Your WORKING DIRECTORY is: $PWD

CONTEXT — read tasks and verify the codebase:
  $FEATURE_DIR/tasks.md

Run checks (tests, linters) as appropriate. Summarize findings or confirm clean.
EOF

log_info "Booting Review phase..."

flowai_ai_run "review" "$INJECTED_PROMPT" "false"

touch "$SIGNALS_DIR/review.ready"
log_success "Review phase complete."
