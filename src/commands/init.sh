#!/usr/bin/env bash
# FlowAI — initialize .flowai in the current repository
# Usage: flowai init [--with-specify]   (Spec Kit bootstrap is optional — can download tools)
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/bootstrap/specify.sh"

WITH_SPECIFY=false
for arg in "$@"; do
  case "$arg" in
    --with-specify) WITH_SPECIFY=true ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  log_error "jq is required. Install jq (e.g. brew install jq) and re-run flowai init."
  exit 1
fi

log_info "Initializing FlowAI in $PWD..."

FLOWAI_DIR="$PWD/.flowai"

if [[ -d "$FLOWAI_DIR" ]] && [[ -f "$FLOWAI_DIR/config.json" ]]; then
  if ! jq -e . "$FLOWAI_DIR/config.json" >/dev/null 2>&1; then
    log_error "Invalid JSON in $FLOWAI_DIR/config.json — fix syntax before continuing."
    exit 1
  fi
  log_warn ".flowai already exists — leaving config in place."
else
  mkdir -p "$FLOWAI_DIR/roles"
  mkdir -p "$FLOWAI_DIR/signals"
  mkdir -p "$FLOWAI_DIR/launch"

  if [[ -f "$PWD/.specify/memory/setup.json" ]]; then
    log_info "Migrating legacy .specify/memory/setup.json → .flowai/config.json"
    cp "$PWD/.specify/memory/setup.json" "$FLOWAI_DIR/config.json"
    jq '.' "$FLOWAI_DIR/config.json" >/dev/null
  else
    cat > "$FLOWAI_DIR/config.json" << 'EOF'
{
  "platform": "generic",
  "default_model": "gpt-4o",
  "master": {
    "tool": "gemini",
    "model": "gpt-4o"
  },
  "layout": "dashboard",
  "auto_approve": false,
  "pipeline": {
    "plan": "team-lead",
    "tasks": "backend-engineer",
    "impl": "backend-engineer",
    "review": "reviewer"
  },
  "roles": {
    "team-lead": { "tool": "gemini", "model": "gpt-4o" },
    "backend-engineer": { "tool": "gemini", "model": "gpt-4o" },
    "reviewer": { "tool": "gemini", "model": "gpt-4o" }
  }
}
EOF
  fi

  log_success "Wrote $FLOWAI_DIR/config.json"
fi

mkdir -p "$PWD/specs"

if ! flowai_specify_is_present "$PWD"; then
  log_warn "Spec Kit (.specify/) not found — feature automation scripts from Spec Kit will be unavailable."
  printf '%s\n' "  • Install manually: https://github.github.io/spec-kit/installation.html"
  log_info "Or run: flowai init --with-specify (needs uv; may download packages)"
  if [[ "$WITH_SPECIFY" == true ]]; then
    log_info "Attempting Spec Kit bootstrap (--with-specify)..."
    flowai_specify_ensure "$PWD" || true
  fi
fi

if [[ ! -f "$FLOWAI_DIR/roles/master.md" ]] && [[ -f "$FLOWAI_HOME/src/roles/master.md" ]]; then
  log_info "Tip: copy bundled roles to customize:"
  for f in "$FLOWAI_HOME/src/roles/"*.md; do
    [[ -f "$f" ]] || continue
    printf "  cp %s %s\n" "$f" "$FLOWAI_DIR/roles/"
  done
fi

log_success "FlowAI is ready."
log_info "Next: customize $FLOWAI_DIR/config.json and optionally copy roles from $FLOWAI_HOME/src/roles/"
log_info "Then run: flowai start"
