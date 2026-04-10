#!/usr/bin/env bash
# FlowAI — Knowledge Graph runtime library
#
# Provides the graph-awareness layer used throughout the FlowAI pipeline:
#   - Checking graph existence and freshness
#   - Reading graph metadata (node/edge counts, build time)
#   - Generating the context block injected into every agent's system prompt
#
# The knowledge graph lives at: .flowai/wiki/
#   GRAPH_REPORT.md  — human+agent readable summary (god nodes, communities, questions)
#   graph.json       — machine-readable graph (nodes, edges, provenance, metadata)
#   index.md         — content catalog updated after every operation
#   log.md           — append-only chronological operation log
#   cache/           — SHA256 file hashes for incremental builds
#
# shellcheck shell=bash

# ─── Constants ────────────────────────────────────────────────────────────────

FLOWAI_WIKI_DIR="${FLOWAI_DIR:-$PWD/.flowai}/wiki"
FLOWAI_GRAPH_REPORT="${FLOWAI_WIKI_DIR}/GRAPH_REPORT.md"
FLOWAI_GRAPH_JSON="${FLOWAI_WIKI_DIR}/graph.json"
FLOWAI_GRAPH_INDEX="${FLOWAI_WIKI_DIR}/index.md"
FLOWAI_GRAPH_LOG="${FLOWAI_WIKI_DIR}/log.md"
FLOWAI_GRAPH_CACHE_DIR="${FLOWAI_WIKI_DIR}/cache"

# ─── Existence & Freshness ────────────────────────────────────────────────────

# Returns 0 if a usable graph exists (GRAPH_REPORT.md + graph.json both present).
flowai_graph_exists() {
  [[ -f "$FLOWAI_GRAPH_REPORT" ]] && [[ -f "$FLOWAI_GRAPH_JSON" ]]
}

# Returns the configured max age in hours (default: 24).
_flowai_graph_max_age_hours() {
  local cfg="${FLOWAI_DIR:-$PWD/.flowai}/config.json"
  if [[ -f "$cfg" ]]; then
    local h
    h="$(jq -r '.graph.max_age_hours // 24' "$cfg" 2>/dev/null)"
    printf '%s' "${h:-24}"
  else
    printf '24'
  fi
}

# Returns 0 if the graph is stale (older than max_age_hours) or missing.
flowai_graph_is_stale() {
  if ! flowai_graph_exists; then
    return 0  # missing = stale
  fi
  local max_hours
  max_hours="$(_flowai_graph_max_age_hours)"
  local max_seconds=$(( max_hours * 3600 ))

  # Use stat to get file age in seconds
  local mtime now age
  if stat -f '%m' "$FLOWAI_GRAPH_REPORT" >/dev/null 2>&1; then
    # macOS stat
    mtime="$(stat -f '%m' "$FLOWAI_GRAPH_REPORT" 2>/dev/null)"
  else
    # GNU stat
    mtime="$(stat -c '%Y' "$FLOWAI_GRAPH_REPORT" 2>/dev/null)"
  fi
  now="$(date +%s)"
  age=$(( now - mtime ))
  [[ "$age" -gt "$max_seconds" ]]
}

# ─── Metadata Readers ─────────────────────────────────────────────────────────

# Read node count from graph.json metadata section.
_flowai_graph_node_count() {
  if [[ -f "$FLOWAI_GRAPH_JSON" ]]; then
    jq -r '.metadata.node_count // (.nodes | length) // 0' "$FLOWAI_GRAPH_JSON" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

# Read edge count from graph.json metadata section.
_flowai_graph_edge_count() {
  if [[ -f "$FLOWAI_GRAPH_JSON" ]]; then
    jq -r '.metadata.edge_count // (.edges | length) // 0' "$FLOWAI_GRAPH_JSON" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

# Read community count from graph.json metadata section.
_flowai_graph_community_count() {
  if [[ -f "$FLOWAI_GRAPH_JSON" ]]; then
    jq -r '.metadata.community_count // 0' "$FLOWAI_GRAPH_JSON" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

# Human-readable relative time since graph was built ("2h ago", "5d ago").
_flowai_graph_age_label() {
  if [[ ! -f "$FLOWAI_GRAPH_REPORT" ]]; then
    printf 'never'
    return
  fi
  local mtime now age
  if stat -f '%m' "$FLOWAI_GRAPH_REPORT" >/dev/null 2>&1; then
    mtime="$(stat -f '%m' "$FLOWAI_GRAPH_REPORT")"
  else
    mtime="$(stat -c '%Y' "$FLOWAI_GRAPH_REPORT")"
  fi
  now="$(date +%s)"
  age=$(( now - mtime ))

  if   [[ "$age" -lt 60 ]];      then printf 'just now'
  elif [[ "$age" -lt 3600 ]];    then printf '%dm ago' "$(( age / 60 ))"
  elif [[ "$age" -lt 86400 ]];   then printf '%dh ago' "$(( age / 3600 ))"
  else                                 printf '%dd ago' "$(( age / 86400 ))"
  fi
}

# ─── Prompt Context Block ─────────────────────────────────────────────────────

# Generate the markdown block injected into every agent's system prompt when a
# graph exists. Teaches agents to navigate the graph instead of grepping raw files.
#
# Design principle: short, directive, concrete. This is read at the start of
# every agent turn — it must be scannable in seconds and act as a navigation map.
flowai_graph_context_block() {
  if ! flowai_graph_exists; then
    return 0
  fi

  local nodes edges communities age wiki_dir
  nodes="$(_flowai_graph_node_count)"
  edges="$(_flowai_graph_edge_count)"
  communities="$(_flowai_graph_community_count)"
  age="$(_flowai_graph_age_label)"
  wiki_dir="${FLOWAI_WIKI_DIR#$PWD/}"  # project-relative path for display

  cat <<GRAPH_BLOCK

--- [FLOWAI KNOWLEDGE GRAPH] ---
A compiled knowledge graph of this codebase is available. Use it as your
primary navigation layer — it is significantly more token-efficient than
reading raw files.

  Graph:  ${wiki_dir}/graph.json
          ${nodes} nodes · ${edges} edges · ${communities} communities · built ${age}

  Start:  ${wiki_dir}/GRAPH_REPORT.md
          → God nodes (highest-degree hubs), community summaries, suggested queries

  Index:  ${wiki_dir}/index.md
          → Full catalog of wiki pages with one-line summaries

Navigation protocol:
  1. Read GRAPH_REPORT.md before searching any files
  2. Use index.md to find the exact wiki page for any concept
  3. Use graph.json for multi-hop reasoning (dependencies, call chains)
  4. Only read raw source files when the graph points you to a specific location
  5. If you discover an undocumented relationship, include it in your response
     so it can be integrated on the next 'flowai graph update' run

Provenance tags in graph.json:
  EXTRACTED   — relationship found directly in source (high confidence)
  INFERRED    — reasonable inference from context (treat as hypothesis)
  AMBIGUOUS   — flagged for human review
---
GRAPH_BLOCK
}

# ─── Path Accessors ───────────────────────────────────────────────────────────

flowai_graph_report_path()  { printf '%s' "$FLOWAI_GRAPH_REPORT"; }
flowai_graph_json_path()    { printf '%s' "$FLOWAI_GRAPH_JSON"; }
flowai_graph_index_path()   { printf '%s' "$FLOWAI_GRAPH_INDEX"; }
flowai_graph_log_path()     { printf '%s' "$FLOWAI_GRAPH_LOG"; }
flowai_graph_cache_dir()    { printf '%s' "$FLOWAI_GRAPH_CACHE_DIR"; }
flowai_graph_wiki_dir()     { printf '%s' "$FLOWAI_WIKI_DIR"; }

# ─── Log Helper ──────────────────────────────────────────────────────────────

# Append an entry to the graph operation log.
# Usage: flowai_graph_log_entry "ingest" "path/to/source.md"
# Format: ## [YYYY-MM-DD] <op> | <detail>
flowai_graph_log_append() {
  local op="$1"
  local detail="${2:-}"
  local date_str
  date_str="$(date +%Y-%m-%d)"
  mkdir -p "$FLOWAI_WIKI_DIR"
  printf '## [%s] %s | %s\n\n' "$date_str" "$op" "$detail" >> "$FLOWAI_GRAPH_LOG"
}

# ─── Graph Enabled Check ──────────────────────────────────────────────────────

# Returns 0 if graph is enabled in config (default: true).
# NOTE: We cannot use jq's `// true` here because jq treats `false` as falsy
# and substitutes the default, making enabled:false silently become true.
flowai_graph_is_enabled() {
  local cfg="${FLOWAI_DIR:-$PWD/.flowai}/config.json"
  if [[ ! -f "$cfg" ]]; then return 0; fi
  local enabled
  enabled="$(jq -r 'if .graph.enabled == null then "true" else (.graph.enabled | tostring) end' "$cfg" 2>/dev/null)"
  [[ "$enabled" != "false" ]]
}
