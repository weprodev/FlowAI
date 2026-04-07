#!/usr/bin/env bash
# FlowAI — start multi-agent tmux session
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/config.sh"
source "$FLOWAI_HOME/src/core/session.sh"
source "$FLOWAI_HOME/src/core/mcp-json.sh"
source "$FLOWAI_HOME/src/bootstrap/specify.sh"

# Headless: create the tmux layout but do not attach (CI / no TTY). Gum is not required —
# phase scripts use gum for approval; headless start does not attach to those UIs.
HEADLESS=false
[[ "${FLOWAI_START_HEADLESS:-}" == "1" ]] && HEADLESS=true
for _fa in "$@"; do
  case "$_fa" in
    --headless) HEADLESS=true ;;
  esac
done

if ! command -v tmux >/dev/null 2>&1; then
  log_error "tmux is not installed. Install it (e.g. brew install tmux) and retry."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  log_error "jq is required for configuration. Install jq (e.g. brew install jq) and retry."
  exit 1
fi

if [[ "$HEADLESS" != true ]]; then
  if [ -t 0 ] && [ "${FLOWAI_TESTING:-0}" != "1" ]; then
    log_info "Start mode: Headless runs in background (CI-safe). Standard attaches interactively."
    if command -v gum >/dev/null 2>&1; then
      if gum confirm "Start in headless mode?"; then
        HEADLESS=true
      fi
    else
      read -r -p "Start in headless mode? [y/N]: " ans < /dev/tty || true
      if [[ "$ans" =~ ^[yY] ]]; then
        HEADLESS=true
      fi
    fi
  fi

  if [[ "$HEADLESS" != true ]] && ! command -v gum >/dev/null 2>&1; then
    log_error "gum is required for phase approval menus. Install gum (e.g. brew install gum)."
    exit 1
  fi
fi

FLOWAI_DIR="$PWD/.flowai"
if [[ ! -d "$FLOWAI_DIR" ]] || [[ ! -f "$FLOWAI_DIR/config.json" ]]; then
  log_error "Not a FlowAI project here — run: flowai init"
  exit 1
fi

if [[ -f "$FLOWAI_DIR/config.json" ]] && ! jq -e . "$FLOWAI_DIR/config.json" >/dev/null 2>&1; then
  log_error "Invalid JSON in $FLOWAI_DIR/config.json — fix syntax or remove and run: flowai init"
  exit 1
fi

export FLOWAI_DIR
export FLOWAI_HOME

# ── Self-healing dependency check ────────────────────────────────────────────
if [[ "${FLOWAI_TESTING:-0}" != "1" ]]; then
  log_header "FlowAI Setup Check"

  _dep_ok()   { printf '  %-14s %s\n' "$1" "${GREEN}✓${RESET} ok"; }
  _dep_warn() { printf '  %-14s %s\n' "$1" "${YELLOW}⚠${RESET}  $2"; }
  _dep_fail() { printf '  %-14s %s\n' "$1" "${RED}✗${RESET}  $2"; }

  for dep in tmux jq gum; do
    if command -v "$dep" >/dev/null 2>&1; then
      _dep_ok "$dep"
    else
      _dep_fail "$dep" "not found — install: brew install $dep"
    fi
  done

  # Node.js — needed for skills.sh and MCP via npx
  if command -v node >/dev/null 2>&1; then
    _dep_ok "node"
  else
    if [ -t 0 ] && command -v brew >/dev/null 2>&1; then
      _dep_warn "node" "required for skills and MCP"
      printf '\n'
      if command -v gum >/dev/null 2>&1; then
        if gum confirm "  Install Node.js via Homebrew now?"; then
          if brew install node; then
            _dep_ok "node"
          else
            _dep_fail "node" "install failed — visit https://nodejs.org"
          fi
        fi
      else
        read -r -p "  Install Node.js via Homebrew? [Y/n]: " _ans < /dev/tty || true
        if [[ ! "$_ans" =~ ^[nN] ]]; then
          if brew install node; then
            _dep_ok "node"
          else
            _dep_fail "node" "install failed"
          fi
        fi
      fi
    else
      _dep_warn "node" "not found — install via https://nodejs.org for skills/MCP support"
    fi
  fi

  # Spec Kit — auto-repair silently
  specify_health="$(flowai_specify_health "$PWD")"
  case "$specify_health" in
    ok)
      _dep_ok "Spec Kit"
      ;;
    seeded)
      _dep_warn "Spec Kit" "using bundled seed — run: uvx ... specify init . to upgrade"
      ;;
    *)
      _dep_warn "Spec Kit" "repairing..."
      flowai_specify_repair "$PWD"
      # Re-check to show accurate state (ok or seeded)
      specify_health="$(flowai_specify_health "$PWD")"
      if [[ "$specify_health" == "ok" ]]; then
        _dep_ok "Spec Kit"
      else
        _dep_warn "Spec Kit" "using bundled seed (offline)"
      fi
      ;;
  esac

  # Initialise mcp.json from config if not yet present
  MCP_JSON="$FLOWAI_DIR/mcp.json"
  if [[ ! -f "$MCP_JSON" ]]; then
    flowai_mcp_emit_runtime_json > "$MCP_JSON" 2>/dev/null || true
  fi

  printf '\n'
fi

SESSION="$(flowai_session_name "$PWD")"
export SESSION

REPO_ROOT="$PWD"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  log_warn "Session '$SESSION' is already running."
  if [[ "$HEADLESS" == true ]]; then
    log_info "Headless: not attaching to existing session."
    exit 0
  fi
  printf "Switching to it... (Ctrl+B D to detach)\n"
  if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "$SESSION"
  else
    tmux attach-session -t "$SESSION"
  fi
  exit 0
fi

log_header "Spinning up FlowAI: $SESSION"

mkdir -p "$FLOWAI_DIR/signals"
mkdir -p "$FLOWAI_DIR/launch"
rm -f "$FLOWAI_DIR/signals"/*.ready 2>/dev/null || true

layout="$(flowai_cfg_layout)"

flowai_write_phase_launcher() {
  local name="$1"
  local phase="$2"
  cat > "$FLOWAI_DIR/launch/tmux_${name}.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export FLOWAI_HOME="$FLOWAI_HOME"
export FLOWAI_DIR="$FLOWAI_DIR"
cd "$REPO_ROOT"
exec "\$FLOWAI_HOME/bin/flowai" run $phase
EOF
  chmod +x "$FLOWAI_DIR/launch/tmux_${name}.sh"
}

flowai_write_phase_launcher "master" "master"

tmux new-session -d -s "$SESSION" -n "master" -x 260 -y 60
tmux set-window-option -t "${SESSION}:master" pane-border-status top
tmux set-window-option -t "${SESSION}:master" pane-border-format " #[bold]#{pane_title}#[default] "
tmux send-keys -t "${SESSION}:master" "bash '$FLOWAI_DIR/launch/tmux_master.sh'" Enter
tmux select-pane -t "${SESSION}:master" -T "👑 Master Agent"

pipelines=(plan tasks impl review)
win_index=1

for phase in "${pipelines[@]}"; do
  flowai_write_phase_launcher "phase_${win_index}" "$phase"
  if [[ "$layout" == "dashboard" ]]; then
    tmux split-window -t "${SESSION}:0" -v
    tmux send-keys -t "${SESSION}:0.${win_index}" "bash '$FLOWAI_DIR/launch/tmux_phase_${win_index}.sh'" Enter
    tmux select-pane -t "${SESSION}:0.${win_index}" -T "🤖 Phase: ${phase}"
  else
    tmux new-window -t "${SESSION}:${win_index}" -n "$phase"
    tmux set-window-option -t "${SESSION}:${win_index}" pane-border-status top
    tmux set-window-option -t "${SESSION}:${win_index}" pane-border-format " #[bold]#{pane_title}#[default] "
    tmux send-keys -t "${SESSION}:${win_index}" "bash '$FLOWAI_DIR/launch/tmux_phase_${win_index}.sh'" Enter
    tmux select-pane -t "${SESSION}:${win_index}" -T "🤖 Phase: ${phase}"
  fi
  win_index=$((win_index + 1))
done

if [[ "$layout" == "dashboard" ]]; then
  tmux select-layout -t "${SESSION}:0" main-vertical
  tmux set-window-option -t "${SESSION}:0" main-pane-width 100
  tmux select-layout -t "${SESSION}:0" main-vertical
  tmux select-pane -t "${SESSION}:0.0"
fi

log_success "Session started."

if [[ "$HEADLESS" == true ]]; then
  log_info "Headless: session is running; not attaching (no TTY)."
  exit 0
fi

if [[ -n "${TMUX:-}" ]]; then
  tmux switch-client -t "$SESSION"
else
  tmux attach-session -t "$SESSION"
fi
