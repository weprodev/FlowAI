#!/usr/bin/env bash
# Ensure GitHub Spec Kit (Specify) scripts exist under .specify/ — optional but recommended for specs/ workflows.
# shellcheck shell=bash

source "$FLOWAI_HOME/src/core/log.sh"

flowai_specify_is_present() {
  local root="${1:-$PWD}"
  [[ -f "$root/.specify/scripts/bash/common.sh" ]]
}

# Best-effort install; returns 0 if .specify is usable afterward.
flowai_specify_ensure() {
  local root="${1:-$PWD}"
  if flowai_specify_is_present "$root"; then
    return 0
  fi

  log_warn "Spec Kit (.specify/) not found — feature scripts (e.g. create-new-feature) will be unavailable."
  log_info "Attempting Spec Kit bootstrap in: $root"

  if command -v uv >/dev/null 2>&1; then
    # Official path: https://github.github.io/spec-kit/installation.html
    if (cd "$root" && uvx --from git+https://github.com/github/spec-kit.git specify init . --script sh 2>/dev/null); then
      if flowai_specify_is_present "$root"; then
        log_success "Spec Kit initialized via uvx (specify init)."
        return 0
      fi
    fi
  fi

  log_warn "Automatic Spec Kit install did not complete (install ${BOLD}uv${RESET} for auto-init, or run specify manually)."
  printf '%s\n' "  • Install manually: https://github.github.io/spec-kit/installation.html" >&2
  printf '%s\n' "  • Or: ${BOLD}uv tool install specify-cli --from git+https://github.com/github/spec-kit.git${RESET} then ${BOLD}specify init . --script sh${RESET}" >&2
  return 1
}
