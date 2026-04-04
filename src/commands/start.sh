#!/usr/bin/env bash
# FlowAI — start multi-agent tmux session
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/config.sh"
source "$FLOWAI_HOME/src/core/session.sh"

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
