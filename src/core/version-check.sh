#!/usr/bin/env bash
# FlowAI — Version check with 24h cache.
#
# Non-blocking, advisory-only check against GitHub Releases.
# Never exits non-zero, never blocks the calling command.
#
# API:
#   flowai_version_check_notify   — print one-line notice if outdated (cached 24h)
#   flowai_version_latest_remote  — fetch latest version from GitHub (raw, no cache)
#   flowai_version_compare A B    — returns 0 if A < B (A is outdated)
#
# shellcheck shell=bash

# GitHub coordinates
FLOWAI_GITHUB_REPO="${FLOWAI_GITHUB_REPO:-weprodev/FlowAI}"
FLOWAI_GITHUB_API="https://api.github.com/repos/${FLOWAI_GITHUB_REPO}/releases/latest"
FLOWAI_UPDATE_CACHE_DIR="${HOME}/.flowai"
FLOWAI_UPDATE_CACHE_FILE="${FLOWAI_UPDATE_CACHE_DIR}/update-check"
FLOWAI_UPDATE_CACHE_TTL=86400  # 24 hours in seconds

# ── Semver comparison ────────────────────────────────────────────────────────
# Returns 0 if ver_a < ver_b (i.e. ver_a is outdated).
# Handles x.y.z format. Strips leading 'v'.
flowai_version_compare() {
  local a="${1#v}" b="${2#v}"
  local a_major a_minor a_patch b_major b_minor b_patch

  IFS='.' read -r a_major a_minor a_patch <<< "$a"
  IFS='.' read -r b_major b_minor b_patch <<< "$b"

  a_major="${a_major:-0}"; a_minor="${a_minor:-0}"; a_patch="${a_patch:-0}"
  b_major="${b_major:-0}"; b_minor="${b_minor:-0}"; b_patch="${b_patch:-0}"

  if (( a_major < b_major )); then return 0; fi
  if (( a_major > b_major )); then return 1; fi
  if (( a_minor < b_minor )); then return 0; fi
  if (( a_minor > b_minor )); then return 1; fi
  if (( a_patch < b_patch )); then return 0; fi
  return 1  # equal or newer
}

# ── Fetch latest version from GitHub ─────────────────────────────────────────
# Prints the latest release tag (e.g. "0.2.0") to stdout.
# Returns 1 on network failure (offline, rate-limited, etc).
flowai_version_latest_remote() {
  local response
  response="$(curl -fsSL --max-time 3 \
    -H "Accept: application/vnd.github.v3+json" \
    "$FLOWAI_GITHUB_API" 2>/dev/null)" || return 1

  local tag
  if command -v jq >/dev/null 2>&1; then
    tag="$(printf '%s' "$response" | jq -r '.tag_name // empty' 2>/dev/null)"
  else
    # Fallback: grep for tag_name in JSON (works without jq)
    tag="$(printf '%s' "$response" | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | grep -oE '"v?[0-9][^"]*"' | tr -d '"')"
  fi

  [[ -z "$tag" ]] && return 1
  # Strip leading 'v' for consistency
  printf '%s' "${tag#v}"
}

# ── Cache management ─────────────────────────────────────────────────────────

_version_check_cache_is_fresh() {
  [[ ! -f "$FLOWAI_UPDATE_CACHE_FILE" ]] && return 1

  local now cached_at age
  now="$(date +%s)"
  cached_at="$(head -1 "$FLOWAI_UPDATE_CACHE_FILE" 2>/dev/null || echo 0)"

  # Validate cached_at is numeric
  [[ "$cached_at" =~ ^[0-9]+$ ]] || return 1

  age=$(( now - cached_at ))
  (( age < FLOWAI_UPDATE_CACHE_TTL ))
}

_version_check_cache_write() {
  local latest="$1"
  mkdir -p "$FLOWAI_UPDATE_CACHE_DIR"
  printf '%s\n%s\n' "$(date +%s)" "$latest" > "$FLOWAI_UPDATE_CACHE_FILE"
}

_version_check_cache_read_latest() {
  [[ -f "$FLOWAI_UPDATE_CACHE_FILE" ]] || return 1
  sed -n '2p' "$FLOWAI_UPDATE_CACHE_FILE" 2>/dev/null
}

# ── Public: non-blocking notification ────────────────────────────────────────
# Call from `flowai start` or any command. Prints a one-liner if outdated.
# Never fails, never blocks for more than 3s.
flowai_version_check_notify() {
  # Skip in test mode, CI, or if explicitly disabled
  [[ "${FLOWAI_TESTING:-0}" == "1" ]] && return 0
  [[ "${FLOWAI_SKIP_UPDATE_CHECK:-0}" == "1" ]] && return 0
  [[ "${CI:-}" == "true" ]] && return 0

  local current latest

  current="$(cat "$FLOWAI_HOME/VERSION" 2>/dev/null || echo "0.0.0")"
  current="${current#v}"

  # Use cache if fresh
  if _version_check_cache_is_fresh; then
    latest="$(_version_check_cache_read_latest)" || return 0
  else
    latest="$(flowai_version_latest_remote)" || return 0
    _version_check_cache_write "$latest"
  fi

  [[ -z "$latest" ]] && return 0

  if flowai_version_compare "$current" "$latest"; then
    # Source log.sh only if not already loaded
    if ! type log_info >/dev/null 2>&1; then
      source "$FLOWAI_HOME/src/core/log.sh" 2>/dev/null || true
    fi
    log_info "FlowAI v${latest} available (current: v${current}). Run: ${BOLD:-}flowai update${RESET:-}"
  fi

  return 0
}
