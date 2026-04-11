#!/usr/bin/env bash
# Install FlowAI — creates flowai + fai commands in PATH.
#
# Modes:
#   ./install.sh            Copy to /usr/local/flowai (production — standalone install)
#   ./install.sh --link     Symlink to this workspace (development — live edits)
#   ./install.sh --uninstall  Remove FlowAI from system
#
# Both modes guarantee ONE source of truth — the other mode is cleaned up automatically.
# shellcheck shell=bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOWAI_SRC="$(CDPATH="" cd "$SCRIPT_DIR" && pwd)"

BOLD=$'\033[1m'
GREEN=$'\033[32m'
CYAN=$'\033[36m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
RESET=$'\033[0m'

# ── Configurable paths ───────────────────────────────────────────────────────
PREFIX="${PREFIX:-${FLOWAI_PREFIX:-/usr/local}}"
DESTDIR="${DESTDIR:-}"
INSTALL_DIR="${DESTDIR}${PREFIX}/flowai"
BIN_DIR="${DESTDIR}${PREFIX}/bin"

# ── Sudo helper ──────────────────────────────────────────────────────────────
_sudo() {
  if [[ "$EUID" -eq 0 || "${NO_SUDO:-0}" == "1" || -n "$DESTDIR" ]]; then
    "$@"
  elif [[ -w "${DESTDIR}${PREFIX}" ]] && [[ -w "${DESTDIR}${PREFIX}/bin" ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

# ── Parse mode ───────────────────────────────────────────────────────────────
MODE="copy"   # default: production install (copy files)
INSTALL_VERSION=""
_prev=""
for arg in "$@"; do
  if [[ "$_prev" == "--version" ]]; then
    INSTALL_VERSION="$arg"
    _prev=""
    continue
  fi
  case "$arg" in
    --link|-l)       MODE="link" ;;
    --uninstall|-u)  MODE="uninstall" ;;
    --version|-v)    _prev="--version" ;;
    --help|-h)
      printf '%bFlowAI installer%b\n\n' "$BOLD" "$RESET"
      printf 'Usage:\n'
      printf '  ./install.sh                      Production install (copy to %s)\n' "$INSTALL_DIR"
      printf '  ./install.sh --link               Developer install (symlink to this workspace)\n'
      printf '  ./install.sh --version <tag>       Install a specific version (e.g. 0.2.0)\n'
      printf '  ./install.sh --uninstall           Remove FlowAI from system\n'
      printf '\nRemote install (no clone required):\n'
      printf '  curl -fsSL https://raw.githubusercontent.com/weprodev/FlowAI/main/install.sh | bash\n'
      printf '  curl ... | bash -s -- --version 0.2.0\n'
      printf '\nMake targets:\n'
      printf '  make install      Same as ./install.sh\n'
      printf '  make link         Same as ./install.sh --link\n'
      printf '  make uninstall    Same as ./install.sh --uninstall\n'
      exit 0
      ;;
  esac
  _prev=""
done

# ── Resolve source ───────────────────────────────────────────────────────────
# If bin/flowai doesn't exist locally, this is a remote install (curl | bash).
# Download the release from GitHub.
if [[ ! -f "$FLOWAI_SRC/bin/flowai" ]]; then
  GITHUB_REPO="${FLOWAI_GITHUB_REPO:-weprodev/FlowAI}"

  if [[ -n "$INSTALL_VERSION" ]]; then
    TAG="v${INSTALL_VERSION#v}"
  else
    # Fetch latest release tag
    printf '%b%sFetching latest FlowAI release...%b\n' "$BOLD" "$CYAN" "$RESET"
    if command -v curl >/dev/null 2>&1; then
      LATEST="$(curl -fsSL --max-time 10 \
        "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null \
        | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' \
        | head -1 | grep -oE '"[^"]*"$' | tr -d '"')" || true
    fi
    if [[ -z "${LATEST:-}" ]]; then
      # Fallback: use main branch
      printf '%b⚠%b Could not fetch latest release. Using main branch.\n' "$YELLOW" "$RESET"
      TAG="main"
    else
      TAG="$LATEST"
    fi
  fi

  printf '  Version: %s\n' "$TAG"

  # Clone the specific tag/branch
  FLOWAI_SRC="$(mktemp -d)"
  trap 'rm -rf "$FLOWAI_SRC"' EXIT

  if ! command -v git >/dev/null 2>&1; then
    # Fallback: download tarball without git
    printf '%b%sDownloading FlowAI %s...%b\n' "$BOLD" "$CYAN" "$TAG" "$RESET"
    TARBALL_URL="https://github.com/${GITHUB_REPO}/archive/refs/tags/${TAG}.tar.gz"
    if ! curl -fsSL --max-time 60 "$TARBALL_URL" -o "$FLOWAI_SRC/flowai.tar.gz" 2>/dev/null; then
      # Try heads (branch) URL
      TARBALL_URL="https://github.com/${GITHUB_REPO}/archive/refs/heads/${TAG}.tar.gz"
      curl -fsSL --max-time 60 "$TARBALL_URL" -o "$FLOWAI_SRC/flowai.tar.gz" 2>/dev/null || {
        printf '%b✗%b Failed to download FlowAI. Check your internet connection.\n' "$RED" "$RESET" >&2
        exit 1
      }
    fi
    tar -xzf "$FLOWAI_SRC/flowai.tar.gz" -C "$FLOWAI_SRC" 2>/dev/null || {
      printf '%b✗%b Failed to extract archive.\n' "$RED" "$RESET" >&2
      exit 1
    }
    EXTRACTED="$(find "$FLOWAI_SRC" -maxdepth 1 -type d -name 'FlowAI-*' | head -1)"
    if [[ -n "$EXTRACTED" ]]; then
      # Move contents up one level
      mv "$EXTRACTED"/* "$EXTRACTED"/.[!.]* "$FLOWAI_SRC/" 2>/dev/null || true
      rmdir "$EXTRACTED" 2>/dev/null || true
    fi
  else
    printf '%b%sCloning FlowAI %s...%b\n' "$BOLD" "$CYAN" "$TAG" "$RESET"
    git clone --depth 1 --branch "$TAG" "https://github.com/${GITHUB_REPO}.git" "$FLOWAI_SRC/repo" >/dev/null 2>&1 || {
      printf '%b✗%b Failed to clone FlowAI. Tag %s may not exist.\n' "$RED" "$RESET" "$TAG" >&2
      exit 1
    }
    # Move contents up
    mv "$FLOWAI_SRC/repo"/* "$FLOWAI_SRC/repo"/.[!.]* "$FLOWAI_SRC/" 2>/dev/null || true
    rm -rf "$FLOWAI_SRC/repo"
  fi

  if [[ ! -f "$FLOWAI_SRC/bin/flowai" ]]; then
    printf '%b✗%b Download succeeded but bin/flowai not found. Archive may be corrupt.\n' "$RED" "$RESET" >&2
    exit 1
  fi
fi

# ── Uninstall ────────────────────────────────────────────────────────────────
if [[ "$MODE" == "uninstall" ]]; then
  printf '%b%sRemoving FlowAI...%b\n' "$BOLD" "$CYAN" "$RESET"
  _sudo rm -f "$BIN_DIR/flowai" "$BIN_DIR/fai"
  if [[ -d "$INSTALL_DIR" ]]; then
    _sudo rm -rf "$INSTALL_DIR"
    printf '  Removed %s\n' "$INSTALL_DIR"
  fi
  printf '%b%s✅ FlowAI uninstalled.%b\n' "$BOLD" "$GREEN" "$RESET"
  exit 0
fi

# ── Cleanup conflicting mode ────────────────────────────────────────────────
# Ensure only ONE mode exists at a time. If switching from copy→link or
# link→copy, remove the remnants of the other mode first.
_cleanup_stale() {
  # If a copied /usr/local/flowai exists and we're switching to link mode, remove it
  if [[ "$MODE" == "link" ]] && [[ -d "$INSTALL_DIR" ]]; then
    # Check it's actually a directory (copy), not a symlink
    if [[ ! -L "$INSTALL_DIR" ]]; then
      printf '  %bCleaning up%b stale copy at %s\n' "$YELLOW" "$RESET" "$INSTALL_DIR"
      _sudo rm -rf "$INSTALL_DIR"
    fi
  fi
  # Remove old symlinks regardless — we'll create fresh ones
  _sudo rm -f "$BIN_DIR/flowai" "$BIN_DIR/fai" 2>/dev/null || true
}

# ── Link mode (developer) ───────────────────────────────────────────────────
if [[ "$MODE" == "link" ]]; then
  printf '%b%sInstalling FlowAI (developer mode — symlink)%b\n' "$BOLD" "$CYAN" "$RESET"
  printf '  Source: %s\n' "$FLOWAI_SRC"

  _cleanup_stale
  _sudo mkdir -p "$BIN_DIR"

  # Create wrapper scripts to cleanly bypass Windows symlink emulation
  _write_wrapper() {
    local target="$1" wrapper="$2"
    _sudo sh -c "cat << 'EOF' > \"$wrapper\"
#!/usr/bin/env bash
export _FLOWAI_WRAPPER_INVOKED_AS=\"\${0##*/}\"
exec \"$target\" \"\$@\"
EOF"
    _sudo chmod +x "$wrapper"
  }

  _write_wrapper "$FLOWAI_SRC/bin/flowai" "$BIN_DIR/flowai"
  _write_wrapper "$FLOWAI_SRC/bin/flowai" "$BIN_DIR/fai"

  printf '\n%b%s✅ FlowAI linked (dev mode).%b\n' "$BOLD" "$GREEN" "$RESET"
  printf '  flowai → %s\n' "$FLOWAI_SRC/bin/flowai"
  printf '  fai    → %s\n' "$FLOWAI_SRC/bin/flowai"
  printf '\n  Edits in %s are immediately live.\n' "$FLOWAI_SRC"
  printf '  No need to reinstall after code changes.\n'
  exit 0
fi

# ── Copy mode (production) ──────────────────────────────────────────────────
printf '%b%sInstalling FlowAI (production mode — copy)%b\n' "$BOLD" "$CYAN" "$RESET"
printf '  Source: %s\n' "$FLOWAI_SRC"
printf '  Target: %s\n' "$INSTALL_DIR"
[[ -n "$DESTDIR" ]] && printf '  DESTDIR: %s\n' "$DESTDIR"

_cleanup_stale
_sudo mkdir -p "$INSTALL_DIR"

if command -v rsync >/dev/null 2>&1; then
  _sudo rsync -a --delete --exclude '.git' --exclude '.flowai' --exclude 'node_modules' --exclude 'bin/fai' "$FLOWAI_SRC/" "$INSTALL_DIR/"
else
  _sudo rm -rf "$INSTALL_DIR"
  _sudo mkdir -p "$INSTALL_DIR"
  _sudo mkdir -p "$INSTALL_DIR/bin"
  _sudo cp "$FLOWAI_SRC/bin/flowai" "$INSTALL_DIR/bin/"
  for item in src models-catalog.json VERSION LICENSE README.md install.sh Makefile; do
    if [[ -e "$FLOWAI_SRC/$item" ]]; then
      _sudo cp -R "$FLOWAI_SRC/$item" "$INSTALL_DIR/"
    fi
  done
fi

_sudo chmod -R a+rX "$INSTALL_DIR"
_sudo chmod +x "$INSTALL_DIR/bin/flowai"

_sudo mkdir -p "$BIN_DIR"
_write_wrapper() {
  local target="$1" wrapper="$2"
  _sudo sh -c "cat << 'EOF' > \"$wrapper\"
#!/usr/bin/env bash
export _FLOWAI_WRAPPER_INVOKED_AS=\"\${0##*/}\"
exec \"$target\" \"\$@\"
EOF"
  _sudo chmod +x "$wrapper"
}

_write_wrapper "$INSTALL_DIR/bin/flowai" "$BIN_DIR/flowai"
_write_wrapper "$INSTALL_DIR/bin/flowai" "$BIN_DIR/fai"

printf '\n%b%s✅ FlowAI installed.%b\n' "$BOLD" "$GREEN" "$RESET"
printf '  flowai → %s/bin/flowai\n' "$INSTALL_DIR"
printf '  fai    → %s/bin/flowai\n' "$INSTALL_DIR"
printf '\n  ⚠  This is a copy. Run %bmake install%b after code changes to update.\n' "$BOLD" "$RESET"
printf '  💡 For development, use %bmake link%b instead (live edits, no reinstall).\n' "$BOLD" "$RESET"
