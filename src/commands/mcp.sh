#!/usr/bin/env bash
# FlowAI — MCP server management command
# Usage: flowai mcp [list|add|remove] [server-id]
# shellcheck shell=bash

set -euo pipefail

# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"
# shellcheck source=src/core/mcp-json.sh
source "$FLOWAI_HOME/src/core/mcp-json.sh"

MCP_CONFIG="$FLOWAI_DIR/mcp.json"

# ─── Built-in catalog ─────────────────────────────────────────────────────────

# Format: id|package|description
_MCP_CATALOG=(
  "context7|@upstash/context7-mcp|Real-time library documentation (default)"
  "github|@modelcontextprotocol/server-github|GitHub API — PRs, issues, branches"
  "filesystem|@modelcontextprotocol/server-filesystem|Local file system operations"
  "postgres|@modelcontextprotocol/server-postgres|PostgreSQL database introspection"
  "gitlab|@modelcontextprotocol/server-gitlab|GitLab API — MRs, issues, pipelines"
)

_mcp_catalog_id()   { echo "${1%%|*}"; }
_mcp_catalog_pkg()  { echo "${1}" | cut -d'|' -f2; }
_mcp_catalog_desc() { echo "${1##*|}"; }

_mcp_require_flowai_dir() {
  if [[ ! -f "$FLOWAI_DIR/config.json" ]]; then
    log_error "Not a FlowAI project — run: flowai init"
    exit 1
  fi
}

_mcp_require_node() {
  if ! command -v node >/dev/null 2>&1; then
    log_error "Node.js is required to use MCP servers."
    printf '%s\n' "  Install: brew install node   (or https://nodejs.org)"
    exit 1
  fi
}

# Initialize mcp.json — seed from config.json defaults if present, otherwise empty.
_mcp_init_file() {
  if [[ -f "$MCP_CONFIG" ]]; then
    return
  fi
  if [[ -f "$FLOWAI_DIR/config.json" ]] && command -v jq >/dev/null 2>&1; then
    if [[ "$(jq '.mcp.servers // {} | length' "$FLOWAI_DIR/config.json" 2>/dev/null)" -gt 0 ]]; then
      flowai_mcp_emit_runtime_json > "$MCP_CONFIG"
      return
    fi
  fi
  printf '{"mcpServers":{}}\n' > "$MCP_CONFIG"
}

# ─── list ─────────────────────────────────────────────────────────────────────

cmd_mcp_list() {
  _mcp_require_flowai_dir

  log_header "MCP Servers"

  printf '\n %s\n' "Configured"
  _mcp_init_file
  local configured_count=0
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    configured_count=$((configured_count + 1))
    local pkg
    pkg="$(jq -r --arg id "$id" '.mcpServers[$id].args[-1] // "(custom)"' "$MCP_CONFIG" 2>/dev/null)"
    local is_default
    is_default="$(jq -r --arg id "$id" '.mcpServers[$id].default // false' "$MCP_CONFIG" 2>/dev/null)"
    if [[ "$is_default" == "true" ]]; then
      log_success "  $id   $pkg  (default)"
    else
      log_success "  $id   $pkg"
    fi
  done < <(jq -r '.mcpServers | keys[]' "$MCP_CONFIG" 2>/dev/null)
  [[ $configured_count -eq 0 ]] && printf '  %s\n' "— none configured"

  printf '\n %s\n' "Available to add"
  local configured_ids
  configured_ids="$(jq -r '.mcpServers | keys | join(" ")' "$MCP_CONFIG" 2>/dev/null)"
  local available_count=0
  for entry in "${_MCP_CATALOG[@]}"; do
    local id="${entry%%|*}"
    local desc="${entry##*|}"
    if ! echo " $configured_ids " | grep -q " $id "; then
      printf '  %s — %s\n' "$id" "$desc"
      available_count=$((available_count + 1))
    fi
  done
  [[ $available_count -eq 0 ]] && printf '  %s\n' "— all catalog servers configured"
  printf '\n  %s\n\n' "→ flowai mcp add"
}

# ─── add ──────────────────────────────────────────────────────────────────────

_mcp_write_server() {
  local id="$1" pkg="$2" is_default="${3:-false}"
  _mcp_init_file
  local tmp
  tmp="$(mktemp)"
  jq --arg id "$id" --arg pkg "$pkg" --argjson def "$is_default" '
    .mcpServers[$id] = {
      "command": "npx",
      "args": ["-y", $pkg],
      "default": $def
    }
  ' "$MCP_CONFIG" > "$tmp" && mv "$tmp" "$MCP_CONFIG" || rm -f "$tmp"
}

cmd_mcp_add() {
  _mcp_require_flowai_dir
  _mcp_require_node
  local target_id="${1:-}"

  if [[ -n "$target_id" ]]; then
    # Direct add from catalog
    local found=false
    for entry in "${_MCP_CATALOG[@]}"; do
      local id="${entry%%|*}"
      if [[ "$id" == "$target_id" ]]; then
        local parts
        IFS='|' read -r -a parts <<< "$entry"
        local pkg="${parts[1]}"
        _mcp_write_server "$id" "$pkg" "false"
        log_success "Added MCP server: $id ($pkg)"
        found=true
        break
      fi
    done
    if [[ "$found" == "false" ]]; then
      log_error "Unknown MCP server: $target_id"
      log_info "Available: context7, github, filesystem, postgres, gitlab"
      exit 1
    fi
    return
  fi

  # Interactive mode
  if ! command -v gum >/dev/null 2>&1; then
    log_error "gum required for interactive mode. Use: flowai mcp add <id>"
    exit 1
  fi

  _mcp_init_file
  local configured_ids
  configured_ids="$(jq -r '.mcpServers | keys | join(" ")' "$MCP_CONFIG" 2>/dev/null)"

  local choices=()
  for entry in "${_MCP_CATALOG[@]}"; do
    local id="${entry%%|*}"
    local desc="${entry##*|}"
    if ! echo " $configured_ids " | grep -q " $id "; then
      local pkg
      pkg="$(echo "$entry" | cut -d'|' -f2)"
      choices+=("${id}  —  ${desc}")
    fi
  done

  if [[ ${#choices[@]} -eq 0 ]]; then
    log_info "All catalog MCP servers are already configured."
    return
  fi

  local selection
  selection="$(gum choose --header "Select MCP server to add:" "${choices[@]}")"
  [[ -z "$selection" ]] && exit 0

  local selected_id
  selected_id="$(echo "$selection" | awk '{print $1}')"

  for entry in "${_MCP_CATALOG[@]}"; do
    local id="${entry%%|*}"
    if [[ "$id" == "$selected_id" ]]; then
      local pkg
      pkg="$(echo "$entry" | cut -d'|' -f2)"
      _mcp_write_server "$id" "$pkg" "false"
      log_success "Added MCP server: $id"
      break
    fi
  done
}

# ─── remove ───────────────────────────────────────────────────────────────────

cmd_mcp_remove() {
  _mcp_require_flowai_dir
  _mcp_init_file

  local ids
  mapfile -t ids < <(jq -r '.mcpServers | keys[]' "$MCP_CONFIG" 2>/dev/null)

  if [[ ${#ids[@]} -eq 0 ]]; then
    log_info "No MCP servers configured."
    return 0
  fi

  local target_id
  if command -v gum >/dev/null 2>&1; then
    target_id="$(gum choose --header "Select MCP server to remove:" "${ids[@]}")"
  else
    printf '%s\n' "${ids[@]}"
    read -r -p "Server ID to remove: " target_id
  fi

  [[ -z "$target_id" ]] && exit 0

  if command -v gum >/dev/null 2>&1; then
    gum confirm "Remove MCP server: $target_id?" || exit 0
  else
    read -r -p "Confirm removal of $target_id? [y/N]: " ans
    [[ "$ans" =~ ^[yY] ]] || exit 0
  fi

  local tmp
  tmp="$(mktemp)"
  jq --arg id "$target_id" 'del(.mcpServers[$id])' "$MCP_CONFIG" > "$tmp" && mv "$tmp" "$MCP_CONFIG" || rm -f "$tmp"
  log_success "Removed MCP server: $target_id"
}

# ─── Entry point ──────────────────────────────────────────────────────────────

subcmd="${1:-}"
shift || true

case "$subcmd" in
  list|"") cmd_mcp_list ;;
  add)     cmd_mcp_add "$@" ;;
  remove)  cmd_mcp_remove ;;
  *)
    log_error "Unknown mcp subcommand: $subcmd"
    printf 'Usage: flowai mcp [list|add|remove] [server-id]\n'
    exit 1
    ;;
esac
