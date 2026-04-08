#!/usr/bin/env bash
# FlowAI — initialize .flowai in the current repository
# Usage: flowai init [--with-specify]   (Spec Kit bootstrap is optional — can download tools)
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/bootstrap/specify.sh"

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
  if [[ -f "$PWD/.specify/memory/setup.json" ]]; then
    mkdir -p "$FLOWAI_DIR/roles"
    mkdir -p "$FLOWAI_DIR/signals"
    mkdir -p "$FLOWAI_DIR/launch"
    log_info "Migrating legacy .specify/memory/setup.json → .flowai/config.json"
    cp "$PWD/.specify/memory/setup.json" "$FLOWAI_DIR/config.json"
    jq '.' "$FLOWAI_DIR/config.json" >/dev/null
  else
    # Bootstrap Spec Kit while the tree is still empty-ish — avoids specify init blocking on "directory not empty"
    # once .flowai/ and specs/ exist.
    if [[ "${FLOWAI_TESTING:-0}" != "1" ]] && ! flowai_specify_is_present "$PWD"; then
      log_info "Bootstrapping Spec Kit (requires uv)..."
      flowai_specify_ensure "$PWD" || true
    fi
    mkdir -p "$FLOWAI_DIR/roles"
    mkdir -p "$FLOWAI_DIR/signals"
    mkdir -p "$FLOWAI_DIR/launch"
    _mc="$FLOWAI_HOME/models-catalog.json"
    _gdef="gemini-2.5-pro"
    _cdef="sonnet"
    if [[ -f "$_mc" ]]; then
      _gdef="$(jq -r '.tools.gemini.default_id // "gemini-2.5-pro"' "$_mc")"
      _cdef="$(jq -r '.tools.claude.default_id // "sonnet"' "$_mc")"
    fi
    jq -n \
      --argjson ra "$(cat "$FLOWAI_HOME/src/core/defaults/skills-role-assignments.json")" \
      --arg gdef "$_gdef" \
      --arg cdef "$_cdef" \
      '{
        platform: "generic",
        default_model: $gdef,
        claude_default_model: $cdef,
        master: { tool: "gemini", model: $gdef },
        layout: "dashboard",
        auto_approve: false,
        pipeline: {
          plan: "team-lead",
          tasks: "backend-engineer",
          impl: "backend-engineer",
          review: "reviewer"
        },
        roles: {
          "team-lead":        { tool: "gemini", model: $gdef },
          "backend-engineer": { tool: "gemini", model: $gdef },
          "reviewer":         { tool: "gemini", model: $gdef }
        },
        skills: { role_assignments: $ra },
        mcp: {
          servers: {
            context7: {
              command: "npx",
              args: ["-y", "@upstash/context7-mcp@latest"],
              description: "Real-time library documentation for AI agents",
              default: true
            }
          }
        }
      }' > "$FLOWAI_DIR/config.json"
  fi

  log_success "Wrote $FLOWAI_DIR/config.json"
fi


mkdir -p "$PWD/specs"

if [ "${FLOWAI_TESTING:-0}" != "1" ]; then
  if ! flowai_specify_is_present "$PWD"; then
    log_info "Attempting Spec Kit bootstrap (requires 'uv')..."
    if ! flowai_specify_ensure "$PWD"; then
      log_warn "Spec Kit automated install failed (is 'uv' installed?)."
      printf '%s\n' "  • Install manually: https://github.github.io/spec-kit/installation.html"
    fi
  fi
fi

if [[ ! -f "$FLOWAI_DIR/roles/master.md" ]] && [[ -f "$FLOWAI_HOME/src/roles/master.md" ]]; then
  log_info "Tip: copy bundled roles to customize:"
  for f in "$FLOWAI_HOME/src/roles/"*.md; do
    [[ -f "$f" ]] || continue
    printf "  cp %s %s\n" "$f" "$FLOWAI_DIR/roles/"
  done
fi

if [[ "${FLOWAI_TESTING:-0}" != "1" ]] && [[ -f "$FLOWAI_DIR/config.json" ]]; then
  export FLOWAI_CONFIG="$FLOWAI_DIR/config.json"
  # shellcheck source=src/core/config-validate.sh
  source "$FLOWAI_HOME/src/core/config-validate.sh"
  if ! flowai_config_validate_models; then
    log_warn "Model fields do not match models-catalog.json — run: flowai validate"
  fi
fi

log_success "FlowAI is ready."
log_info "Next: customize $FLOWAI_DIR/config.json and optionally copy roles from $FLOWAI_HOME/src/roles/"
log_info "Then run: flowai validate && flowai start"
