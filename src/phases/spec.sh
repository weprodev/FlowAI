#!/usr/bin/env bash
# FlowAI — Spec artifact phase (usually driven by Master role content).
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/ai.sh"
source "$FLOWAI_HOME/src/core/phase.sh"

ROLE_FILE="$(flowai_phase_resolve_role_prompt "master")"

log_info "Booting Spec phase..."

FEATURE_DIR="$(flowai_phase_resolve_feature_dir)"
if [[ -z "$FEATURE_DIR" ]]; then
  log_error "No feature directory under specs/. Create one (e.g. make specify / Spec Kit) or mkdir specs/<branch>."
  exit 1
fi

export INJECTED_PROMPT="$FLOWAI_DIR/launch/spec_prompt.md"
mkdir -p "$FLOWAI_DIR/launch"

cat <<EOF > "$INJECTED_PROMPT"
$(cat "$ROLE_FILE")

IMPORTANT PIPELINE DIRECTIVE:
You are assigned to Phase: Specification.
Your WORKING DIRECTORY is: $PWD

OUTPUT FILE — you MUST write your artifact to this exact path:
  $FEATURE_DIR/spec.md

Complete your phase tasks as thoroughly as possible. When you finish, exit immediately.
EOF

while true; do
  flowai_ai_run "master" "$INJECTED_PROMPT" "false"
  flowai_phase_verify_artifact "$FEATURE_DIR/spec.md" "Specification" "spec"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    break
  fi
  if [[ "$rc" -eq 2 ]]; then
    rm -f "$SIGNALS_DIR/spec.reject" 2>/dev/null || true
    flowai_phase_wait_for "spec.revision" "Spec revision"
    rm -f "$SIGNALS_DIR/spec.revision.ready" 2>/dev/null || true
  fi
done
