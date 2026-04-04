#!/usr/bin/env bash
# FlowAI — Implement phase
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/ai.sh"
source "$FLOWAI_HOME/src/phases/lib.sh"

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

export INJECTED_PROMPT="$FLOWAI_DIR/launch/impl_prompt.md"
mkdir -p "$FLOWAI_DIR/launch"

cat <<EOF > "$INJECTED_PROMPT"
$(cat "$ROLE_FILE")

IMPORTANT PIPELINE DIRECTIVE:
You are assigned to Phase: Implement (Code Writing).
Your WORKING DIRECTORY is: $PWD

CONTEXT — read the following upstream artifact before starting:
  $FEATURE_DIR/tasks.md

Implement the code required in tasks.md. Check off tasks as you complete them.
When blockers remain, document them and exit.
EOF

log_info "Booting Implement phase..."

while true; do
  flowai_ai_run "impl" "$INJECTED_PROMPT" "false"

  decision=""
  if command -v gum >/dev/null 2>&1; then
    decision="$(gum choose 'Approve Implementation' 'Needs changes')"
  else
    read -r -p "Approve implementation? [y/N]: " decision < /dev/tty || true
    [[ "$decision" =~ ^[yY] ]] && decision="Approve Implementation" || decision="Needs changes"
  fi

  if [[ "$decision" == "Approve Implementation" ]]; then
    touch "$SIGNALS_DIR/impl.ready"
    log_success "Implementation phase approved."
    break
  fi

  touch "$SIGNALS_DIR/impl.reject" 2>/dev/null || true
  log_warn "Implementation needs changes — coordinate with Master."
  flowai_phase_wait_for "impl.revision" "Implement revision"
  rm -f "$SIGNALS_DIR/impl.revision.ready" 2>/dev/null || true
done
