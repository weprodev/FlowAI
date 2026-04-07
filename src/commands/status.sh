#!/usr/bin/env bash
# FlowAI — unified status command
# Shows session, config, Spec Kit, skills, and MCP health in one view.
# shellcheck shell=bash

set -euo pipefail

# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"
# shellcheck source=src/core/session.sh
source "$FLOWAI_HOME/src/core/session.sh"
# Spec Kit check is optional — if specify.sh fails to source (e.g. restricted PATH), skip gracefully
if [[ -f "$FLOWAI_HOME/src/bootstrap/specify.sh" ]]; then
  # shellcheck source=src/bootstrap/specify.sh
  source "$FLOWAI_HOME/src/bootstrap/specify.sh" 2>/dev/null || true
fi

_status_check() {
  local label="$1" value="$2" ok="$3"
  local width=12
  printf '  %-*s' "$width" "$label"
  if [[ "$ok" == "true" ]]; then
    printf "${GREEN}✓${RESET} %s\n" "$value"
  elif [[ "$ok" == "warn" ]]; then
    printf "${YELLOW}⚠${RESET} %s\n" "$value"
  else
    printf "${RED}✗${RESET} %s\n" "$value"
  fi
}

# ── tmux guard (must be first — session name computation requires tools) ───────
if ! command -v tmux >/dev/null 2>&1; then
  log_error "tmux is not installed. Install: brew install tmux"
  exit 1
fi

SESSION="$(flowai_session_name "$PWD")"
PROJECT_NAME="${PWD##*/}"

log_header "FlowAI — $PROJECT_NAME ($SESSION)"

# ── Session ──────────────────────────────────────────────────────────────────
if tmux has-session -t "$SESSION" 2>/dev/null; then
  win_count="$(tmux list-windows -t "$SESSION" 2>/dev/null | wc -l | tr -d ' ')"
  _status_check "Session" "running ($win_count windows)" "true"
else
  _status_check "Session" "not running — use: flowai start" "warn"
fi

# ── Config ───────────────────────────────────────────────────────────────────
if [[ -f "$FLOWAI_DIR/config.json" ]]; then
  if jq -e . "$FLOWAI_DIR/config.json" >/dev/null 2>&1; then
    _status_check "Config" ".flowai/config.json" "true"
  else
    _status_check "Config" ".flowai/config.json (invalid JSON!)" "false"
  fi
else
  _status_check "Config" "not found — run: flowai init" "false"
fi

# ── Spec Kit ─────────────────────────────────────────────────────────────────
specify_health="$(flowai_specify_health "$PWD")"
case "$specify_health" in
  ok)     _status_check "Spec Kit" ".specify/ (full install)" "true" ;;
  seeded) _status_check "Spec Kit" ".specify/ (seeded fallback)" "warn" ;;
  *)      _status_check "Spec Kit" "not found — flowai start will repair" "false" ;;
esac

# ── Skills ───────────────────────────────────────────────────────────────────
bundled_count=0
if [[ -d "$FLOWAI_HOME/src/skills" ]]; then
  bundled_count="$(find "$FLOWAI_HOME/src/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')"
fi
installed_count=0
if [[ -d "$FLOWAI_DIR/skills" ]]; then
  installed_count="$(find "$FLOWAI_DIR/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')"
fi
_status_check "Skills" "${bundled_count} bundled · ${installed_count} installed" "true"

# ── MCP ──────────────────────────────────────────────────────────────────────
MCP_CONFIG="$FLOWAI_DIR/mcp.json"
if [[ -f "$MCP_CONFIG" ]]; then
  mcp_count="$(jq '.mcpServers | length' "$MCP_CONFIG" 2>/dev/null || echo 0)"
  mcp_names="$(jq -r '.mcpServers | keys | join(", ")' "$MCP_CONFIG" 2>/dev/null || echo "")"
  if [[ "$mcp_count" -gt 0 ]]; then
    _status_check "MCP" "${mcp_count} configured (${mcp_names})" "true"
  else
    _status_check "MCP" "none — try: flowai mcp add" "warn"
  fi
else
  _status_check "MCP" "none — try: flowai mcp add" "warn"
fi

printf '\n'
