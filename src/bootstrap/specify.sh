#!/usr/bin/env bash
# FlowAI — GitHub Spec Kit bootstrap and management module
# Handles install, seed fallback, health checks, and auto-repair.
# shellcheck shell=bash

# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"

# ─── Health check ────────────────────────────────────────────────────────────

# Returns 0 if .specify is fully functional (has the signal script).
flowai_specify_is_present() {
  local root="${1:-$PWD}"
  [[ -f "$root/.specify/scripts/bash/common.sh" ]]
}

# Returns: ok | seeded | missing
flowai_specify_health() {
  local root="${1:-$PWD}"
  if ! [[ -d "$root/.specify" ]]; then
    echo "missing"
    return
  fi
  if [[ -f "$root/.specify/scripts/bash/common.sh" ]]; then
    # Distinguish real Spec Kit from our seed using jq for reliable JSON parsing
    if jq -e '.seeded_by // "" | test("flowai")' "$root/.specify/memory/setup.json" >/dev/null 2>&1; then
      echo "seeded"
    else
      echo "ok"
    fi
  else
    echo "missing"
  fi
}

# ─── Seed fallback ────────────────────────────────────────────────────────────

# Copy bundled seed skeleton when network/uv is unavailable.
# This guarantees signal-protocol compatibility with zero external dependencies.
flowai_specify_seed_fallback() {
  local root="${1:-$PWD}"
  local seed="$FLOWAI_HOME/src/bootstrap/specify-seed"

  log_warn "Using bundled Spec Kit seed (offline fallback)."
  log_info "Install via: uvx --from git+https://github.com/github/spec-kit.git specify init . --ai claude --script sh"

  mkdir -p "$root/.specify/scripts/bash"
  mkdir -p "$root/.specify/memory"
  mkdir -p "$root/.specify/signals"

  cp "$seed/scripts/bash/common.sh" "$root/.specify/scripts/bash/common.sh"
  cp "$seed/memory/setup.json"      "$root/.specify/memory/setup.json"

  # Only write constitution if user hasn't customized it
  if [[ ! -f "$root/.specify/memory/constitution.md" ]]; then
    cp "$seed/memory/constitution.md" "$root/.specify/memory/constitution.md"
  fi

  log_success "Spec Kit seed applied — signal protocol available."
}

# ─── Install (non-interactive) ───────────────────────────────────────────────

# Best-effort real Spec Kit install. Passes --ai and --script to suppress wizard.
# Returns 0 if usable afterward (real or seeded).
flowai_specify_ensure() {
  local root="${1:-$PWD}"

  if flowai_specify_is_present "$root"; then
    return 0
  fi

  local agent
  agent="$(command -v claude >/dev/null 2>&1 && echo "claude" || echo "gemini")"

  if command -v uv >/dev/null 2>&1; then
    log_info "Installing Spec Kit (non-interactive)..."
    # --ai suppresses the editor/model picker; finite y's answer "merge into non-empty dir?" without SIGPIPE
    # from `yes|head` breaking pipefail while uvx still exits 0.
    # shellcheck disable=SC2016
    if (cd "$root" && set -o pipefail && { printf 'y\n%.0s' {1..120}; } | uvx --from git+https://github.com/github/spec-kit.git \
        specify init . --ai "$agent" --script sh); then
      if flowai_specify_is_present "$root"; then
        log_success "Spec Kit initialized."
        return 0
      fi
    fi
    log_warn "Spec Kit install did not complete. Falling back to seed."
  else
    log_warn "uv not found. Falling back to bundled Spec Kit seed."
  fi

  flowai_specify_seed_fallback "$root"
}

# ─── Auto-repair (called by flowai start) ────────────────────────────────────

# Detects state and repairs silently. Never interacts with user.
flowai_specify_repair() {
  local root="${1:-$PWD}"
  local health
  health="$(flowai_specify_health "$root")"

  case "$health" in
    ok)     return 0 ;;
    seeded) return 0 ;;       # Seed is functional — no action needed
    missing)
      flowai_specify_ensure "$root"
      ;;
  esac
}

# ─── Constitution helper ─────────────────────────────────────────────────────

# Returns path to constitution or empty string if absent.
flowai_specify_constitution_path() {
  local root="${1:-$PWD}"
  local path="$root/.specify/memory/constitution.md"
  [[ -f "$path" ]] && echo "$path" || echo ""
}
