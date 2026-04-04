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

export INJECTED_PROMPT="$FLOWAI_DIR/launch/plan_prompt.md"
mkdir -p "$FLOWAI_DIR/launch"

cat <<EOF > "$INJECTED_PROMPT"
$(cat "$ROLE_FILE")

IMPORTANT PIPELINE DIRECTIVE:
You are assigned to Phase: Plan (Architecture).
Your WORKING DIRECTORY is: $PWD

CONTEXT — read the following upstream artifact before starting:
  $FEATURE_DIR/spec.md

OUTPUT FILE — you MUST write your artifact to this exact path:
  $FEATURE_DIR/plan.md

Complete your phase tasks as thoroughly as possible. When you finish, exit immediately.
EOF

log_info "Booting Plan phase..."

while true; do
  flowai_ai_run "plan" "$INJECTED_PROMPT" "false"
  flowai_phase_verify_artifact "$FEATURE_DIR/plan.md" "Plan" "plan"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    break
  fi
  if [[ "$rc" -eq 2 ]]; then
    rm -f "$SIGNALS_DIR/plan.reject" 2>/dev/null || true
    flowai_phase_wait_for "plan.revision" "Plan revision"
    rm -f "$SIGNALS_DIR/plan.revision.ready" 2>/dev/null || true
  fi
done
