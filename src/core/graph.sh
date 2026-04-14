#!/usr/bin/env bash
# FlowAI — Knowledge Graph runtime library
#
# Provides the graph-awareness layer used throughout the FlowAI pipeline:
#   - Checking graph existence and freshness
#   - Reading graph metadata (node/edge counts, build time)
#   - Generating the context block injected into every agent's system prompt
#
# Machine graph + cache live under the wiki directory (default `.flowai/wiki/`).
# Override with `graph.wiki_dir` in `.flowai/config.json` or `FLOWAI_GRAPH_WIKI_DIR`.
# `GRAPH_REPORT.md` is separate (default `docs/GRAPH_REPORT.md` if `docs/` exists).
#
# shellcheck shell=bash

# Default relative path for compiled graph data (kept under `.flowai/` with session state).
FLOWAI_GRAPH_WIKI_DIR_DEFAULT=".flowai/wiki"

# ─── Path resolution (run with cwd = project root) ───────────────────────────

# Sets: FLOWAI_WIKI_DIR, FLOWAI_GRAPH_REPORT, FLOWAI_GRAPH_JSON, FLOWAI_GRAPH_INDEX,
#       FLOWAI_GRAPH_LOG, FLOWAI_GRAPH_CACHE_DIR
flowai_graph_resolve_paths() {
  local root
  root="$(pwd -P 2>/dev/null || printf '%s' "$PWD")"
  local fd="${FLOWAI_DIR:-$root/.flowai}"

  if [[ -n "${FLOWAI_GRAPH_WIKI_DIR:-}" ]]; then
    if [[ "${FLOWAI_GRAPH_WIKI_DIR}" == /* ]]; then
      FLOWAI_WIKI_DIR="${FLOWAI_GRAPH_WIKI_DIR}"
    else
      FLOWAI_WIKI_DIR="${root}/${FLOWAI_GRAPH_WIKI_DIR}"
    fi
  else
    local wiki_rel="$FLOWAI_GRAPH_WIKI_DIR_DEFAULT"
    if type flowai_cfg_read >/dev/null 2>&1 && [[ -f "${fd}/config.json" ]]; then
      wiki_rel="$(flowai_cfg_read '.graph.wiki_dir' "$FLOWAI_GRAPH_WIKI_DIR_DEFAULT")"
      [[ -z "$wiki_rel" || "$wiki_rel" == "null" ]] && wiki_rel="$FLOWAI_GRAPH_WIKI_DIR_DEFAULT"
    fi
    if [[ "$wiki_rel" == /* ]]; then
      FLOWAI_WIKI_DIR="$wiki_rel"
    else
      FLOWAI_WIKI_DIR="${root}/${wiki_rel}"
    fi
  fi

  FLOWAI_GRAPH_JSON="${FLOWAI_WIKI_DIR}/graph.json"
  FLOWAI_GRAPH_INDEX="${FLOWAI_WIKI_DIR}/index.md"
  FLOWAI_GRAPH_LOG="${FLOWAI_WIKI_DIR}/log.md"
  FLOWAI_GRAPH_CACHE_DIR="${FLOWAI_WIKI_DIR}/cache"

  mkdir -p "$FLOWAI_WIKI_DIR" 2>/dev/null || true

  if [[ -n "${FLOWAI_GRAPH_REPORT_PATH:-}" ]]; then
    FLOWAI_GRAPH_REPORT="${FLOWAI_GRAPH_REPORT_PATH}"
    return 0
  fi

  local _cfg_report_path=""
  if type flowai_cfg_read >/dev/null 2>&1; then
    _cfg_report_path="$(flowai_cfg_read '.graph.report_path' '')"
  fi

  if [[ -n "$_cfg_report_path" ]]; then
    if [[ "$_cfg_report_path" == /* ]]; then
      FLOWAI_GRAPH_REPORT="${_cfg_report_path}"
    else
      FLOWAI_GRAPH_REPORT="${root}/${_cfg_report_path}"
    fi
  elif [[ -d "${root}/docs" ]]; then
    FLOWAI_GRAPH_REPORT="${root}/docs/GRAPH_REPORT.md"
  else
    FLOWAI_GRAPH_REPORT="${root}/GRAPH_REPORT.md"
  fi
}

flowai_graph_resolve_paths

# ─── Path Helpers ─────────────────────────────────────────────────────────────

# Resolve the physical project root (symlink-free).
# On macOS, /var is a symlink to /private/var. When bash cd's into a mktemp
# directory, $PWD may use /var/... while pwd -P returns /private/var/...,
# causing ${file#$PWD/} to fail silently. Normalizing through pwd -P ensures
# consistent path comparison.
_graph_project_root() {
  pwd -P
}

# Convert an absolute file path to a project-relative path.
# Handles both /var/... and /private/var/... forms on macOS.
_graph_rel_path() {
  local file="$1"
  local root
  root="$(_graph_project_root)"
  # Try stripping the physical root first
  local rel="${file#"$root"/}"
  if [[ "$rel" == "$file" ]]; then
    # Stripping failed — file path uses a different symlink form.
    # Resolve the file's directory physically and reconstruct.
    local dir base
    dir="$(cd "$(dirname "$file")" 2>/dev/null && pwd -P)"
    base="$(basename "$file")"
    rel="${dir}/${base}"
    rel="${rel#"$root"/}"
  fi
  printf '%s' "$rel"
}

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

  local nodes edges communities bridges age wiki_dir
  nodes="$(_flowai_graph_node_count)"
  edges="$(_flowai_graph_edge_count)"
  communities="$(_flowai_graph_community_count)"
  bridges="$(jq -r '.metadata.bridge_edge_count // 0' "$FLOWAI_GRAPH_JSON" 2>/dev/null | tr -d '\r')"
  age="$(_flowai_graph_age_label)"
  wiki_dir="$(_graph_rel_path "$FLOWAI_WIKI_DIR")"  # project-relative path for display

  # Embed the actual graph report content so the agent already HAS the codebase
  # map without needing to read a file. Instructions like "read GRAPH_REPORT.md
  # first" are consistently ignored — embedding the content is the only reliable
  # approach. Truncate to first 200 lines to keep prompt size reasonable.
  local report_content=""
  if [[ -f "$FLOWAI_GRAPH_REPORT" ]]; then
    report_content="$(head -200 "$FLOWAI_GRAPH_REPORT" 2>/dev/null || true)"
  fi

  cat <<GRAPH_BLOCK

--- [FLOWAI KNOWLEDGE GRAPH — CODEBASE MAP] ---
${nodes} nodes · ${edges} edges · ${communities} communities · ${bridges} bridges · built ${age}

FILES: graph.json=${wiki_dir}/graph.json | index=${wiki_dir}/index.md

USE THIS MAP to navigate the codebase. Do NOT search files blindly — the graph
already maps every entity, relationship, and community. Only read a source file
when you need specific implementation details that the graph summary below
does not cover.

${report_content}

Provenance: EXTRACTED=high confidence | INFERRED=hypothesis | AMBIGUOUS=needs review
For multi-hop queries (dependencies, call chains): read ${wiki_dir}/graph.json
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
