#!/usr/bin/env bash
# FlowAI — Tasks phase
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/ai.sh"
source "$FLOWAI_HOME/src/phases/lib.sh"

flowai_phase_wait_for "plan" "Tasks Phase"

FEATURE_DIR="$(flowai_phase_resolve_feature_dir)"
if [[ -z "$FEATURE_DIR" ]]; then
  log_error "No feature directory under specs/."
  exit 1
fi

ROLE_FILE="$(flowai_phase_resolve_role_prompt "tasks")"

export INJECTED_PROMPT="$FLOWAI_DIR/launch/tasks_prompt.md"
mkdir -p "$FLOWAI_DIR/launch"

cat <<EOF > "$INJECTED_PROMPT"
$(cat "$ROLE_FILE")

IMPORTANT PIPELINE DIRECTIVE:
You are assigned to Phase: Tasks (Implementation Breakdown).
Your WORKING DIRECTORY is: $PWD

CONTEXT — read the following upstream artifact before starting:
  $FEATURE_DIR/plan.md

OUTPUT FILE — you MUST write your artifact to this exact path:
  $FEATURE_DIR/tasks.md

Complete your phase tasks as thoroughly as possible. When you finish, exit immediately.
EOF

log_info "Booting Tasks phase..."

while true; do
  flowai_ai_run "tasks" "$INJECTED_PROMPT" "false"
  flowai_phase_verify_artifact "$FEATURE_DIR/tasks.md" "Tasks" "tasks"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    break
  fi
  if [[ "$rc" -eq 2 ]]; then
    rm -f "$SIGNALS_DIR/tasks.reject" 2>/dev/null || true
    flowai_phase_wait_for "tasks.revision" "Tasks revision"
    rm -f "$SIGNALS_DIR/tasks.revision.ready" 2>/dev/null || true
  fi
done
