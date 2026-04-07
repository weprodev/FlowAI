#!/usr/bin/env bash
# Minimal MCP JSON for Claude --mcp-config (command + args only).
# shellcheck shell=bash

# shellcheck source=src/core/config.sh
source "$FLOWAI_HOME/src/core/config.sh"

# JSON object: server id -> { command, args }
flowai_mcp_servers_minimal_from_config() {
  jq '.mcp.servers // {} | map_values({command: .command, args: .args})' \
    "$FLOWAI_CONFIG" 2>/dev/null || echo '{}'
}

# Full document: { "mcpServers": { ... } }
flowai_mcp_emit_runtime_json() {
  jq -n --argjson servers "$(flowai_mcp_servers_minimal_from_config)" \
    '{mcpServers: $servers}'
}
