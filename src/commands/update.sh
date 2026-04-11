#!/usr/bin/env bash
# FlowAI — Self-update command.
#
# Usage:
#   flowai update              Update to latest release
#   flowai update --check      Just check, don't update
#   flowai update --version X  Update to specific version
#
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/version-check.sh"

FLOWAI_GITHUB_REPO="${FLOWAI_GITHUB_REPO:-weprodev/FlowAI}"

# ── Mode detection ───────────────────────────────────────────────────────────
# Returns: "link" | "copy" | "git-clone"
_update_detect_mode() {
  # Check if FLOWAI_HOME is a symlinked dev workspace
  if [[ -d "$FLOWAI_HOME/.git" ]]; then
    # It's a git repo. Is it the developer's workspace (make link)?
    local origin
    origin="$(git -C "$FLOWAI_HOME" remote get-url origin 2>/dev/null || true)"
    if [[ -n "$origin" ]]; then
      # Check if the bin/flowai symlink points here (make link mode)
      local real_bin
      real_bin="$(readlink /usr/local/bin/flowai 2>/dev/null || true)"
      if [[ "$real_bin" == "$FLOWAI_HOME/bin/flowai" ]]; then
        printf 'link'
        return
      fi
      printf 'git-clone'
      return
    fi
  fi
  printf 'copy'
}

# ── Help ─────────────────────────────────────────────────────────────────────
_update_usage() {
  cat <<EOF
${BOLD:-}flowai update — Self-update FlowAI${RESET:-}

Usage:
  flowai update              Update to the latest release
  flowai update --check      Check for updates without installing
  flowai update --version X  Update to a specific version (e.g. 0.2.0)

Modes:
  Developer (make link):  Tells you to use 'git pull'
  Production (make install):  Downloads and replaces the installed copy
  Git clone:  Runs 'git pull' automatically
EOF
}

# ── Update via download ──────────────────────────────────────────────────────
_update_download_and_install() {
  local target_version="$1"
  local tag="v${target_version#v}"

  local tarball_url="https://github.com/${FLOWAI_GITHUB_REPO}/archive/refs/tags/${tag}.tar.gz"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' RETURN

  log_info "Downloading FlowAI ${tag}..."

  if ! curl -fsSL --max-time 30 "$tarball_url" -o "$tmp_dir/flowai.tar.gz" 2>/dev/null; then
    # Fallback: try without 'v' prefix
    tarball_url="https://github.com/${FLOWAI_GITHUB_REPO}/archive/refs/tags/${target_version}.tar.gz"
    if ! curl -fsSL --max-time 30 "$tarball_url" -o "$tmp_dir/flowai.tar.gz" 2>/dev/null; then
      log_error "Failed to download FlowAI ${tag}. Check your internet connection."
      log_info "You can also update manually: git clone --branch ${tag} https://github.com/${FLOWAI_GITHUB_REPO}.git && cd FlowAI && make install"
      return 1
    fi
  fi

  log_info "Extracting..."
  tar -xzf "$tmp_dir/flowai.tar.gz" -C "$tmp_dir" 2>/dev/null || {
    log_error "Failed to extract archive. The release tag '${tag}' may not exist."
    return 1
  }

  # Find the extracted directory (GitHub names it FlowAI-<tag>)
  local extracted_dir
  extracted_dir="$(find "$tmp_dir" -maxdepth 1 -type d -name 'FlowAI-*' | head -1)"
  if [[ -z "$extracted_dir" ]] || [[ ! -f "$extracted_dir/install.sh" ]]; then
    log_error "Unexpected archive layout. Expected install.sh in extracted directory."
    return 1
  fi

  log_info "Installing ${tag}..."
  bash "$extracted_dir/install.sh" || {
    log_error "Install failed. You may need to run with sudo: sudo bash $extracted_dir/install.sh"
    return 1
  }

  local new_version
  new_version="$(cat "$FLOWAI_HOME/VERSION" 2>/dev/null || echo "unknown")"
  log_success "FlowAI updated to v${new_version}"
}

# ── Update via git pull ──────────────────────────────────────────────────────
_update_git_pull() {
  local target_version="${1:-}"

  log_info "Updating FlowAI via git pull..."

  if [[ -n "$target_version" ]]; then
    local tag="v${target_version#v}"
    log_info "Fetching tags..."
    git -C "$FLOWAI_HOME" fetch --tags 2>/dev/null || {
      log_error "Git fetch failed. Check your internet connection."
      return 1
    }
    # Check if tag exists
    if ! git -C "$FLOWAI_HOME" rev-parse "$tag" >/dev/null 2>&1; then
      # Try without 'v' prefix
      if ! git -C "$FLOWAI_HOME" rev-parse "$target_version" >/dev/null 2>&1; then
        log_error "Tag '${tag}' not found. Available tags:"
        git -C "$FLOWAI_HOME" tag --sort=-v:refname | head -10
        return 1
      fi
      tag="$target_version"
    fi
    log_info "Checking out ${tag}..."
    git -C "$FLOWAI_HOME" checkout "$tag" 2>/dev/null || {
      log_error "Failed to checkout ${tag}."
      return 1
    }
  else
    git -C "$FLOWAI_HOME" pull --ff-only 2>/dev/null || {
      log_warn "git pull --ff-only failed. You may have local changes."
      log_info "Try: cd $FLOWAI_HOME && git stash && git pull && git stash pop"
      return 1
    }
  fi

  local new_version
  new_version="$(cat "$FLOWAI_HOME/VERSION" 2>/dev/null || echo "unknown")"
  log_success "FlowAI updated to v${new_version}"
}

# ── Main ─────────────────────────────────────────────────────────────────────

CHECK_ONLY=false
TARGET_VERSION=""

for arg in "$@"; do
  case "$arg" in
    --check|-c)        CHECK_ONLY=true ;;
    --version)         :; ;;  # value comes next
    -h|--help|help)    _update_usage; exit 0 ;;
    *)
      # Capture version value after --version
      if [[ "${_prev_arg:-}" == "--version" ]]; then
        TARGET_VERSION="$arg"
      fi
      ;;
  esac
  _prev_arg="$arg"
done

# Read current version
CURRENT_VERSION="$(cat "$FLOWAI_HOME/VERSION" 2>/dev/null || echo "0.0.0")"
CURRENT_VERSION="${CURRENT_VERSION#v}"

log_header "FlowAI Update"
printf '\n'
log_info "Current version: v${CURRENT_VERSION}"
log_info "Install location: ${FLOWAI_HOME}"

# Detect install mode
MODE="$(_update_detect_mode)"
log_info "Install mode: ${MODE}"
printf '\n'

# ── Check only mode ──────────────────────────────────────────────────────────
if [[ "$CHECK_ONLY" == "true" ]]; then
  if [[ -n "$TARGET_VERSION" ]]; then
    log_info "Target version: v${TARGET_VERSION}"
    if flowai_version_compare "$CURRENT_VERSION" "$TARGET_VERSION"; then
      log_info "Update available: v${CURRENT_VERSION} → v${TARGET_VERSION}"
    else
      log_success "Already at v${CURRENT_VERSION} (≥ v${TARGET_VERSION})"
    fi
  else
    log_info "Checking GitHub for latest release..."
    LATEST="$(flowai_version_latest_remote)" || {
      log_warn "Could not reach GitHub. Check your internet connection."
      exit 0
    }
    log_info "Latest release: v${LATEST}"
    if flowai_version_compare "$CURRENT_VERSION" "$LATEST"; then
      log_info "Update available: v${CURRENT_VERSION} → v${LATEST}"
      log_info "Run: flowai update"
    else
      log_success "Already up to date (v${CURRENT_VERSION})"
    fi
  fi
  exit 0
fi

# ── Dev link mode: use git pull ──────────────────────────────────────────────
if [[ "$MODE" == "link" ]]; then
  log_info "Developer mode detected (make link)."
  log_info "Your flowai commands run directly from: ${FLOWAI_HOME}"
  printf '\n'
  log_info "To update, use git in your workspace:"
  printf '  cd %s && git pull\n' "$FLOWAI_HOME"
  printf '\n'
  exit 0
fi

# ── Resolve target version ──────────────────────────────────────────────────
if [[ -z "$TARGET_VERSION" ]]; then
  log_info "Checking GitHub for latest release..."
  TARGET_VERSION="$(flowai_version_latest_remote)" || {
    log_error "Could not reach GitHub. Check your internet connection."
    exit 1
  }
  log_info "Latest release: v${TARGET_VERSION}"
fi

# Already up to date?
if ! flowai_version_compare "$CURRENT_VERSION" "$TARGET_VERSION"; then
  log_success "Already up to date (v${CURRENT_VERSION})"
  exit 0
fi

log_info "Updating: v${CURRENT_VERSION} → v${TARGET_VERSION}"
printf '\n'

# ── Execute update ───────────────────────────────────────────────────────────
if [[ "$MODE" == "git-clone" ]]; then
  _update_git_pull "$TARGET_VERSION"
else
  _update_download_and_install "$TARGET_VERSION"
fi

# Invalidate version check cache
rm -f "${HOME}/.flowai/update-check" 2>/dev/null || true
