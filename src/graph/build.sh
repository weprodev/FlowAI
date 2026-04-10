#!/usr/bin/env bash
# FlowAI — Knowledge Graph build engine
#
# Implements a dual-pass extraction pipeline:
#   Pass 1: Deterministic structural extraction (pure bash/grep, no LLM)
#           Extracts: files, functions, imports, call edges, module dependencies
#   Pass 2: Semantic extraction (LLM via flowai_ai_run)
#           Extracts: concepts, design rationale, architectural decisions
#           Tags all edges as EXTRACTED / INFERRED / AMBIGUOUS
#
# Then merges both passes + runs community detection to produce:
#   graph.json      — full graph with nodes, edges, provenance, metadata
#   GRAPH_REPORT.md — human+agent readable summary
#   index.md        — content catalog
#
# Uses SHA256 content hashing for incremental builds: only changed files
# trigger a re-extraction. Unchanged files reuse their cached results.
#
# shellcheck shell=bash

# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"
# shellcheck source=src/core/config.sh
source "$FLOWAI_HOME/src/core/config.sh"
# shellcheck source=src/core/graph.sh
source "$FLOWAI_HOME/src/core/graph.sh"

# ─── Configuration ────────────────────────────────────────────────────────────

_graph_scan_paths() {
  local cfg="${FLOWAI_DIR}/config.json"
  if [[ -f "$cfg" ]]; then
    local paths
    paths="$(jq -r '.graph.scan_paths // ["src","docs","specs"] | .[]' "$cfg" 2>/dev/null)"
    if [[ -n "$paths" ]]; then
      echo "$paths"
      return
    fi
  fi
  # defaults
  printf 'src\ndocs\nspecs\n'
}

_graph_ignore_patterns() {
  local cfg="${FLOWAI_DIR}/config.json"
  if [[ -f "$cfg" ]]; then
    jq -r '.graph.ignore_patterns // [] | .[]' "$cfg" 2>/dev/null
  fi
}

# Optional LLM semantic extraction (costly; off by default — see graph.semantic_enabled).
_graph_semantic_enabled() {
  local cfg="${FLOWAI_DIR:-$PWD/.flowai}/config.json"
  if [[ ! -f "$cfg" ]]; then
    return 1
  fi
  local v
  v="$(jq -r 'if .graph.semantic_enabled == null then "false" else (.graph.semantic_enabled | tostring) end' "$cfg" 2>/dev/null)"
  [[ "$v" == "true" ]]
}

# Run semantic extraction for discovered files (best-effort; populates .flowai/wiki/cache/semantic/).
_graph_run_semantic_pass() {
  local force="${1:-false}"
  log_info "Pass 2: Semantic extraction (LLM)..." >&2
  local processed=0 skipped=0
  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    if [[ "$force" != "true" ]] && _graph_file_is_cached "$file"; then
      local rel_path="${file#$PWD/}"
      local cache_key semantic_file
      cache_key="$(printf '%s' "$rel_path" | tr '/' '_').json"
      semantic_file="${FLOWAI_GRAPH_CACHE_DIR}/semantic/${cache_key}"
      if [[ -f "$semantic_file" ]]; then
        skipped=$(( skipped + 1 ))
        continue
      fi
    fi
    _graph_semantic_extract_file "$file" >/dev/null
    processed=$(( processed + 1 ))
  done < <(_graph_discover_files)
  log_success "Semantic pass: ${processed} processed · ${skipped} skipped (unchanged)" >&2
}

# ─── File Discovery ───────────────────────────────────────────────────────────

# Discover all candidate files in scan_paths, respecting ignore_patterns.
# Outputs: one absolute file path per line.
_graph_discover_files() {
  local -a ignore_args=()
  local pat
  while IFS= read -r pat; do
    [[ -z "$pat" ]] && continue
    ignore_args+=(-not -name "$pat" -not -path "*/$pat")
  done < <(_graph_ignore_patterns)

  # Always exclude binary-heavy and dependency directories
  ignore_args+=(
    -not -path "*/node_modules/*"
    -not -path "*/.git/*"
    -not -path "*/vendor/*"
    -not -path "*/.flowai/wiki/*"
    -not -path "*/.flowai/graph-cache/*"
    -not -name "*.png" -not -name "*.jpg" -not -name "*.gif"
    -not -name "*.woff" -not -name "*.woff2" -not -name "*.ttf"
    -not -name "*.zip" -not -name "*.tar" -not -name "*.gz"
  )

  local scan_dir
  while IFS= read -r scan_dir; do
    [[ -z "$scan_dir" ]] && continue
    local abs_dir="$PWD/$scan_dir"
    [[ -d "$abs_dir" ]] || continue
    find "$abs_dir" -type f "${ignore_args[@]}" 2>/dev/null
  done < <(_graph_scan_paths)
}

# ─── SHA256 Cache ─────────────────────────────────────────────────────────────

# Compute SHA256 of a file (cross-platform: sha256sum or shasum).
_graph_sha256() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    # Fallback: use file mtime+size as a coarse fingerprint
    stat -f '%m%z' "$file" 2>/dev/null || stat -c '%Y%s' "$file" 2>/dev/null || echo "0"
  fi
}

# Cache file path for a given source file (maps path → SHA256).
_graph_cache_key_file() {
  local file="$1"
  local key
  key="$(printf '%s' "$file" | tr '/' '_' | tr ' ' '_')"
  printf '%s/%s.sha' "$FLOWAI_GRAPH_CACHE_DIR" "$key"
}

# Returns 0 if cached SHA256 matches current file SHA256 (file not changed).
_graph_file_is_cached() {
  local file="$1"
  local cache_file
  cache_file="$(_graph_cache_key_file "$file")"
  [[ -f "$cache_file" ]] || return 1
  local cached_hash current_hash
  cached_hash="$(cat "$cache_file")"
  current_hash="$(_graph_sha256 "$file")"
  [[ "$cached_hash" == "$current_hash" ]]
}

# Update the cache for a file.
_graph_cache_update() {
  local file="$1"
  local cache_file
  cache_file="$(_graph_cache_key_file "$file")"
  mkdir -p "$FLOWAI_GRAPH_CACHE_DIR"
  _graph_sha256 "$file" > "$cache_file"
}

# ─── Pass 1: Structural Extraction ────────────────────────────────────────────

# Emit JSON for a single node.
_graph_node_json() {
  local id="$1" label="$2" type="$3" path="$4"
  jq -n --arg id "$id" --arg label "$label" --arg type "$type" --arg path "$path" \
    '{"id":$id,"label":$label,"type":$type,"path":$path}'
}

# Emit JSON for a single edge.
_graph_edge_json() {
  local source="$1" target="$2" relation="$3" provenance="$4" confidence="${5:-1.0}"
  jq -n \
    --arg s "$source" --arg t "$target" \
    --arg r "$relation" --arg p "$provenance" --arg c "$confidence" \
    '{"source":$s,"target":$t,"relation":$r,"provenance":$p,"confidence":($c|tonumber)}'
}

# ─── Spec Detection ───────────────────────────────────────────────────────────

# Returns 0 if the file is a spec document (higher semantic authority than source).
# Spec files live in specs/, .specify/, or have naming conventions like *.spec.md,
# requirements*.md, user-story*.md, acceptance*.md, RFC*.md.
_graph_is_spec_file() {
  local file="$1"
  local rel="${file#$PWD/}"

  # Path-based: lives in a spec directory
  [[ "$rel" == specs/* ]] && return 0
  [[ "$rel" == .specify/* ]] && return 0
  [[ "$rel" == spec/* ]] && return 0

  # Name-based: naming conventions for spec documents
  local base
  base="$(basename "$file" | tr '[:upper:]' '[:lower:]')"
  case "$base" in
    *.spec.md|requirements*.md|acceptance*.md|user-story*.md|\
    rfc*.md|adr*.md|prd*.md|feature*.md) return 0 ;;
    spec.md|requirements.md|acceptance.md) return 0 ;;
  esac

  return 1
}

# Extract spec metadata from a spec file: feature IDs, acceptance criteria headings.
# Returns JSON: {feature_ids: [...], criteria: [...], title: ""}
_graph_extract_spec_meta() {
  local file="$1"

  # Feature/story IDs: patterns like UC-XXX-NNN, FEAT-NNN, STORY-NNN, REQ-NNN
  local feature_ids
  feature_ids="$(grep -oE '\b(UC|FEAT|STORY|REQ|RFC|ADR|US)-[A-Z0-9_-]+' "$file" 2>/dev/null | \
    sort -u | head -20 | jq -Rs 'split("\n") | map(select(. != ""))' 2>/dev/null || echo '[]')"

  # Acceptance criteria / given-when-then markers
  local criteria
  criteria="$(grep -oE '^#{1,3}[[:space:]]+(Acceptance|Given|When|Then|Must|Should|Shall)[^\n]{0,80}' \
    "$file" 2>/dev/null | sed 's/^#*[[:space:]]*//' | head -10 | \
    jq -Rs 'split("\n") | map(select(. != ""))' 2>/dev/null || echo '[]')"

  # Title: first H1
  local title
  title="$(grep -m1 '^# ' "$file" 2>/dev/null | sed 's/^# //' || echo "$(basename "$file")")"

  jq -n \
    --argjson fids "$feature_ids" \
    --argjson crit "$criteria" \
    --arg title "$title" \
    '{"feature_ids":$fids,"criteria":$crit,"title":$title}'
}

# Extract structural relationships from a single file using grep-based heuristics.
# This is language-agnostic and dependency-free. Returns a partial graph fragment (JSON).
_graph_structural_extract_file() {
  local file="$1"
  local rel_path="${file#$PWD/}"
  local file_id
  file_id="$(printf '%s' "$rel_path" | tr '/' '.' | sed 's/\.\(sh\|md\|json\|js\|ts\|go\|py\|rb\|java\|rs\)$//')"

  local nodes=()
  local edges=()

  # ── Spec files: elevated node type with spec-specific metadata ──────────────
  if _graph_is_spec_file "$file"; then
    local spec_meta
    spec_meta="$(_graph_extract_spec_meta "$file")"
    local spec_title
    spec_title="$(printf '%s' "$spec_meta" | jq -r '.title' 2>/dev/null || basename "$file")"

    # Spec node carries richer metadata
    nodes+=("$(jq -n \
      --arg id "$file_id" \
      --arg label "$spec_title" \
      --arg path "$rel_path" \
      --argjson meta "$spec_meta" \
      '{"id":$id,"label":$label,"type":"spec","path":$path,
        "feature_ids":$meta.feature_ids,"criteria":$meta.criteria,
        "trust":"HIGH"}')")

    # SPECIFIES edges: look for references to src/ paths (impl traceability)
    while IFS= read -r linked; do
      [[ -z "$linked" ]] && continue
      [[ "$linked" == http* ]] && continue
      local link_id
      link_id="$(printf '%s' "$linked" | tr '/' '.' | sed 's/^\.//;s/\.\(sh\|md\|json\|js\|ts\)$//')"
      edges+=("$(_graph_edge_json "$file_id" "$link_id" "SPECIFIES" "EXTRACTED")")
    done < <(grep -oE '\]\(([^)]+)\)' "$file" 2>/dev/null | grep -oE '\(([^)]+)\)' | tr -d '()' | \
               grep -vE '^https?://' || true)
  else
    # Standard file node
    nodes+=("$(_graph_node_json "$file_id" "$(basename "$file")" "file" "$rel_path")")
  fi

  # ── Bash: source/import detection ─────────────────────────────────────────
  if [[ "$file" == *.sh ]]; then
    while IFS= read -r dep; do
      [[ -z "$dep" ]] && continue
      local dep_id
      dep_id="$(printf '%s' "$dep" | tr '/' '.' | sed 's/\.\(sh\)$//')"
      edges+=("$(_graph_edge_json "$file_id" "$dep_id" "sources" "EXTRACTED")")
    done < <(grep -oE 'source[[:space:]]+"?\$\{?FLOWAI_HOME\}?/([^"[:space:]]+\.sh)' "$file" 2>/dev/null | \
             grep -oE 'src/[^"[:space:]]+\.sh' || true)

    # Function definitions (one graph node per matching top-level function)
    while IFS= read -r fn_line; do
      [[ -z "$fn_line" ]] && continue
      local fn
      fn="$(printf '%s' "$fn_line" | sed 's/^[[:space:]]*//;s/().*$//')"
      [[ -z "$fn" ]] && continue
      local fn_id="${file_id}.${fn}"
      nodes+=("$(_graph_node_json "$fn_id" "$fn" "function" "$rel_path")")
      edges+=("$(_graph_edge_json "$file_id" "$fn_id" "defines" "EXTRACTED")")
    done < <(grep -E '^[[:space:]]*(flowai_[a-z_]+|_[a-z_]+)\(\)' "$file" 2>/dev/null || true)
  fi

  # ── Markdown: link/reference detection (non-spec files) ────────────────────
  if [[ "$file" == *.md ]] && ! _graph_is_spec_file "$file"; then
    while IFS= read -r linked; do
      [[ -z "$linked" ]] && continue
      [[ "$linked" == http* ]] && continue
      local link_id
      link_id="$(printf '%s' "$linked" | tr '/' '.' | sed 's/^\.//;s/\.\(md\)$//')"
      edges+=("$(_graph_edge_json "$file_id" "$link_id" "references" "EXTRACTED")")
    done < <(grep -oE '\]\(([^)]+)\)' "$file" 2>/dev/null | grep -oE '\(([^)]+)\)' | tr -d '()' || true)
  fi

  # ── JSON: config dependency mapping ───────────────────────────────────────
  if [[ "$file" == *.json ]]; then
    # Extract top-level keys as concepts
    while IFS= read -r key; do
      [[ -z "$key" ]] && continue
      local key_id="${file_id}.${key}"
      nodes+=("$(_graph_node_json "$key_id" "$key" "config_key" "$rel_path")")
      edges+=("$(_graph_edge_json "$file_id" "$key_id" "contains" "EXTRACTED")")
    done < <(jq -r 'keys[]' "$file" 2>/dev/null | head -20 || true)
  fi

  # Output partial graph fragment — collect nodes and edges into temp JSONL files
  # and then build the final JSON fragment
  local tmp_n tmp_e
  tmp_n="$(mktemp /tmp/flowai_frag_nodes.XXXXXX.jsonl)"
  tmp_e="$(mktemp /tmp/flowai_frag_edges.XXXXXX.jsonl)"

  for n in "${nodes[@]:-}"; do
    [[ -n "$n" ]] && printf '%s\n' "$n" >> "$tmp_n" || true
  done
  for e in "${edges[@]:-}"; do
    [[ -n "$e" ]] && printf '%s\n' "$e" >> "$tmp_e" || true
  done

  local nodes_arr edges_arr
  nodes_arr="$(jq -sc '.' "$tmp_n" 2>/dev/null || echo '[]')"
  edges_arr="$(jq -sc '.' "$tmp_e" 2>/dev/null || echo '[]')"
  rm -f "$tmp_n" "$tmp_e"

  jq -n \
    --argjson nodes "$nodes_arr" \
    --argjson edges "$edges_arr" \
    '{"nodes":$nodes,"edges":$edges}'
}

# Run the full structural pass over all (changed) files.
# Writes output to: .flowai/wiki/cache/structural.json
_graph_run_structural_pass() {
  local force="${1:-false}"
  local cache_dir="$FLOWAI_GRAPH_CACHE_DIR/structural"
  mkdir -p "$cache_dir"

  local processed=0 cached=0 total=0

  # Use temp files for incremental JSON accumulation (avoids bash array/string issues)
  local tmp_nodes tmp_edges
  tmp_nodes="$(mktemp /tmp/flowai_struct_nodes.XXXXXX.jsonl)"
  tmp_edges="$(mktemp /tmp/flowai_struct_edges.XXXXXX.jsonl)"

  log_info "Pass 1: Structural extraction..." >&2

  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    total=$(( total + 1 ))
    local rel="${file#$PWD/}"
    local fragment_cache="$cache_dir/$(printf '%s' "$rel" | tr '/' '_').json"

    if [[ "$force" != "true" ]] && _graph_file_is_cached "$file" && [[ -f "$fragment_cache" ]]; then
      # Append cached fragment's nodes/edges to accumulators
      jq -c '.nodes[]' "$fragment_cache" >> "$tmp_nodes" 2>/dev/null || true
      jq -c '.edges[]' "$fragment_cache" >> "$tmp_edges" 2>/dev/null || true
      cached=$(( cached + 1 ))
      continue
    fi

    local fragment
    fragment="$(_graph_structural_extract_file "$file")"
    printf '%s' "$fragment" > "$fragment_cache"

    # Append this fragment's nodes/edges to JSONL accumulators
    printf '%s' "$fragment" | jq -c '.nodes[]' >> "$tmp_nodes" 2>/dev/null || true
    printf '%s' "$fragment" | jq -c '.edges[]' >> "$tmp_edges" 2>/dev/null || true

    _graph_cache_update "$file"
    processed=$(( processed + 1 ))
  done < <(_graph_discover_files)

  log_success "Structural pass: ${total} files (${processed} processed · ${cached} cached)" >&2

  # Convert JSONL accumulators to proper JSON arrays
  local structural_file="${FLOWAI_GRAPH_CACHE_DIR}/structural.json"

  local nodes_array edges_array
  if [[ -s "$tmp_nodes" ]]; then
    nodes_array="$(jq -sc '.' "$tmp_nodes" 2>/dev/null || echo '[]')"
  else
    nodes_array='[]'
  fi
  if [[ -s "$tmp_edges" ]]; then
    edges_array="$(jq -sc '.' "$tmp_edges" 2>/dev/null || echo '[]')"
  else
    edges_array='[]'
  fi

  jq -n \
    --argjson nodes "$nodes_array" \
    --argjson edges "$edges_array" \
    '{"nodes":$nodes,"edges":$edges}' > "$structural_file"

  rm -f "$tmp_nodes" "$tmp_edges"
  # NOTE: output path printed to stdout for caller; log output goes to stderr
}

# ─── Pass 2: Semantic Extraction via LLM ──────────────────────────────────────

# Generate the LLM prompt for semantic extraction from a single file.
_graph_semantic_prompt() {
  local file="$1"
  local rel_path="${file#$PWD/}"
  local content
  content="$(head -200 "$file" 2>/dev/null)"  # First 200 lines — enough for concept extraction

  cat <<PROMPT
You are extracting a knowledge graph fragment from a project file.
File: ${rel_path}

Your task is to return ONLY valid JSON. No explanation, no markdown fences.

Extract the key concepts and relationships from the content below.
For each relationship, tag it:
  "EXTRACTED" — directly stated in the source
  "INFERRED"  — reasonable inference from context (include confidence: 0.0-1.0)
  "AMBIGUOUS" — uncertain, needs review

Return this exact JSON structure:
{
  "nodes": [
    {"id": "unique.dot.separated.id", "label": "Human readable name", "type": "concept|function|module|pattern|decision", "summary": "one sentence"}
  ],
  "edges": [
    {"source": "id1", "target": "id2", "relation": "verb phrase", "provenance": "EXTRACTED|INFERRED|AMBIGUOUS", "confidence": 1.0}
  ],
  "insights": ["One sentence architectural insight worth preserving (max 3)"]
}

File content:
---
${content}
---
PROMPT
}

# Run semantic extraction on a single file via the configured AI tool.
# Returns the semantic fragment JSON path.
_graph_semantic_extract_file() {
  local file="$1"
  local rel_path="${file#$PWD/}"
  local cache_dir="$FLOWAI_GRAPH_CACHE_DIR/semantic"
  mkdir -p "$cache_dir"

  local cache_key
  cache_key="$(printf '%s' "$rel_path" | tr '/' '_').json"
  local cache_file="${cache_dir}/${cache_key}"

  # Return cached result if file hasn't changed
  if _graph_file_is_cached "$file" && [[ -f "$cache_file" ]]; then
    printf '%s' "$cache_file"
    return 0
  fi

  # Write prompt to temp file for flowai_ai_run
  local prompt_file
  prompt_file="$(mktemp /tmp/flowai_graph_prompt.XXXXXX)"
  _graph_semantic_prompt "$file" > "$prompt_file"

  # Use the master agent's tool/model (graph extraction doesn't need full pipeline agents)
  local tool model
  tool="$(flowai_cfg_read '.master.tool' 'gemini')"
  model="$(flowai_cfg_read '.master.model' '')"

  # Invoke AI and capture JSON output
  local raw_output
  if command -v flowai_tool_"${tool}"_run_oneshot >/dev/null 2>&1; then
    # Prefer non-interactive oneshot mode if the tool supports it
    raw_output="$(flowai_tool_"${tool}"_run_oneshot "$model" "$prompt_file" 2>/dev/null || echo '{}')"
  else
    # Fallback: write placeholder; semantic pass is best-effort
    raw_output='{"nodes":[],"edges":[],"insights":[]}'
  fi
  rm -f "$prompt_file"

  # Validate JSON before caching
  if printf '%s' "$raw_output" | jq -e . >/dev/null 2>&1; then
    printf '%s' "$raw_output" > "$cache_file"
  else
    printf '{"nodes":[],"edges":[],"insights":[]}' > "$cache_file"
  fi

  printf '%s' "$cache_file"
}

# ─── Graph Merge ─────────────────────────────────────────────────────────────

# Merge structural.json + all semantic fragment files into graph.json.
# Deduplicates nodes by id, annotates edges with provenance, writes metadata.
_graph_merge() {
  local structural_file="$1"
  local semantic_dir="$FLOWAI_GRAPH_CACHE_DIR/semantic"
  local output_file="$FLOWAI_GRAPH_JSON"

  log_info "Merging structural + semantic passes..."

  # Collect all semantic fragment files
  local semantic_files=()
  if [[ -d "$semantic_dir" ]]; then
    while IFS= read -r f; do
      [[ -f "$f" ]] && semantic_files+=("$f")
    done < <(find "$semantic_dir" -name "*.json" 2>/dev/null)
  fi

  # Build the merged graph via jq
  local struct_nodes struct_edges
  struct_nodes="$(jq '.nodes // []' "$structural_file" 2>/dev/null)"
  struct_edges="$(jq '.edges // []' "$structural_file" 2>/dev/null)"

  local sem_nodes='[]' sem_edges='[]' all_insights='[]'

  for sf in "${semantic_files[@]}"; do
    local snodes sedges insights
    snodes="$(jq '.nodes // []' "$sf" 2>/dev/null)"
    sedges="$(jq '.edges // []' "$sf" 2>/dev/null)"
    insights="$(jq '.insights // []' "$sf" 2>/dev/null)"
    sem_nodes="$(jq -n --argjson a "$sem_nodes" --argjson b "$snodes" '$a + $b')"
    sem_edges="$(jq -n --argjson a "$sem_edges" --argjson b "$sedges" '$a + $b')"
    all_insights="$(jq -n --argjson a "$all_insights" --argjson b "$insights" '$a + $b')"
  done

  # Merge all nodes (deduplicate by id, structural takes precedence)
  # Merge all edges
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  jq -n \
    --argjson sn "$struct_nodes" \
    --argjson se "$struct_edges" \
    --argjson mn "$sem_nodes" \
    --argjson me "$sem_edges" \
    --argjson insights "$all_insights" \
    --arg built_at "$now" \
    '{
      "metadata": {
        "built_at": $built_at,
        "version": "1.0",
        "node_count": (($sn + $mn) | unique_by(.id) | length),
        "edge_count": (($se + $me) | length),
        "community_count": 0,
        "spec_count": (($sn + $mn) | map(select(.type == "spec")) | length),
        "specifies_edge_count": (($se + $me) | map(select(.relation == "SPECIFIES")) | length),
        "implements_edge_count": (($se + $me) | map(select(.relation == "IMPLEMENTS")) | length),
        "evolution_event_count": 0,
        "specs_with_git_activity": 0
      },
      "nodes": (($sn + $mn) | unique_by(.id)),
      "edges": ($se + $me),
      "insights": ($insights | unique)
    }' > "$output_file"

  local node_count edge_count
  node_count="$(jq '.metadata.node_count' "$output_file")"
  edge_count="$(jq '.metadata.edge_count' "$output_file")"

  log_success "Graph merged: ${node_count} nodes · ${edge_count} edges"
}

# ─── Community Detection ──────────────────────────────────────────────────────

# Lightweight degree-based community detection (pure jq/bash).
# No external dependencies. Groups nodes by their highest-degree neighbors.
# Updates metadata.community_count in graph.json.
_graph_detect_communities() {
  local graph_file="$FLOWAI_GRAPH_JSON"
  [[ -f "$graph_file" ]] || return 0

  log_info "Detecting communities (degree-based clustering)..."

  # Write jq program to a temp file to avoid shell quoting issues with 'as' bindings
  local jq_prog_file
  jq_prog_file="$(mktemp /tmp/flowai_community.XXXXXX.jq)"
  cat > "$jq_prog_file" <<'JQ_PROG'
reduce .edges[] as $e
  ({};
   .[$e.source] = ((.[$e.source] // 0) + 1) |
   .[$e.target] = ((.[$e.target] // 0) + 1)
  ) as $degree |
  input |
  .nodes |= map(
    . + {
      "degree": ($degree[.id] // 0),
      "community": (
        if ($degree[.id] // 0) >= 10 then "god"
        elif ($degree[.id] // 0) >= 5 then "hub"
        else "leaf"
        end
      )
    }
  ) |
  . + {
    "metadata": (.metadata + {
      "community_count": (.nodes | map(.community) | unique | length)
    })
  }
JQ_PROG

  local updated
  updated="$(jq --null-input -f "$jq_prog_file" --jsonargs < "$graph_file" 2>/dev/null || true)"
  rm -f "$jq_prog_file"

  # Simpler fallback: degree-annotate nodes directly
  if [[ -z "$updated" ]]; then
    updated="$(jq '
      ([ .edges[] | .source, .target ] | group_by(.) | map({key: .[0], value: length}) | from_entries) as $deg |
      .nodes |= map(. + {
        "degree": ($deg[.id] // 0),
        "community": (if ($deg[.id] // 0) >= 10 then "god" elif ($deg[.id] // 0) >= 5 then "hub" else "leaf" end)
      }) |
      .metadata.community_count = (.nodes | map(.community) | unique | length)
    ' "$graph_file" 2>/dev/null || cat "$graph_file")"
  fi

  if [[ -n "$updated" ]]; then
    printf '%s' "$updated" > "$graph_file"
  fi

  local communities
  communities="$(jq '.metadata.community_count // 0' "$graph_file")"
  log_success "Community detection: ${communities} communities identified"
}

# ─── GRAPH_REPORT.md Generation ───────────────────────────────────────────────

# Generate the human+agent readable summury of the knowledge graph.
_graph_generate_report() {
  local graph_file="$FLOWAI_GRAPH_JSON"
  local report_file="$FLOWAI_GRAPH_REPORT"
  [[ -f "$graph_file" ]] || return 1

  log_info "Generating GRAPH_REPORT.md..."

  local built_at node_count edge_count community_count
  built_at="$(jq -r '.metadata.built_at' "$graph_file")"
  node_count="$(jq -r '.metadata.node_count' "$graph_file")"
  edge_count="$(jq -r '.metadata.edge_count' "$graph_file")"
  community_count="$(jq -r '.metadata.community_count // 0' "$graph_file")"

  # Top god nodes by degree (descending)
  local god_nodes
  god_nodes="$(jq -r '
    .nodes |
    sort_by(-.degree) |
    .[0:10] |
    .[] |
    "- **\(.label)** (\(.path // .id)) — degree \(.degree // 0)"
  ' "$graph_file" 2>/dev/null)"

  # Collect all architectural insights from semantic pass
  local insights
  insights="$(jq -r '
    .insights // [] | .[0:10] | .[] | "- \(.)"
  ' "$graph_file" 2>/dev/null)"

  # AMBIGUOUS edges (flagged for review)
  local ambiguous_edges
  ambiguous_edges="$(jq -r '
    .edges |
    map(select(.provenance == "AMBIGUOUS")) |
    .[0:5] |
    .[] |
    "- \(.source) → \(.target) (\(.relation))"
  ' "$graph_file" 2>/dev/null)"

  # Spec coverage — specs with SPECIFIES edges pointing to real code
  local spec_count specifies_count implements_count spec_nodes_list
  spec_count="$(jq -r '.metadata.spec_count // 0' "$graph_file")"
  specifies_count="$(jq -r '.metadata.specifies_edge_count // 0' "$graph_file")"
  implements_count="$(jq -r '.metadata.implements_edge_count // 0' "$graph_file")"

  # Spec status counts for the dashboard (YAML/frontmatter — not the same as git chronicle)
  local cnt_planned cnt_inprogress cnt_implemented cnt_deprecated
  cnt_planned="$(jq '[.nodes[] | select(.type=="spec" and .status=="planned")] | length' "$graph_file" 2>/dev/null || echo 0)"
  cnt_inprogress="$(jq '[.nodes[] | select(.type=="spec" and .status=="in-progress")] | length' "$graph_file" 2>/dev/null || echo 0)"
  cnt_implemented="$(jq '[.nodes[] | select(.type=="spec" and .status=="implemented")] | length' "$graph_file" 2>/dev/null || echo 0)"
  cnt_deprecated="$(jq '[.nodes[] | select(.type=="spec" and (.status=="deprecated" or .status=="superseded"))] | length' "$graph_file" 2>/dev/null || echo 0)"

  # Git-derived evolution (Karpathy wiki: compiled, incremental history — not re-parsing git each time)
  local evo_event_total specs_with_git_trail
  evo_event_total="$(jq -r '.metadata.evolution_event_count // 0' "$graph_file")"
  specs_with_git_trail="$(jq -r '.metadata.specs_with_git_activity // 0' "$graph_file")"

  spec_nodes_list="$(jq -r '
    .nodes |
    map(select(.type == "spec")) |
    sort_by(.label) |
    .[] |
    "- **\(.label)** (`\(.path)`) " +
    "[\(.status // "unknown")] " +
    (if .since != null then "· since `\(.since)` " else "" end) +
    (if .author != null then "· \(.author) " else "" end) +
    "— IDs: " + ((.feature_ids // []) | if length > 0 then join(", ") else "none" end) +
    " · " + ((.criteria // []) | length | tostring) + " criteria"
  ' "$graph_file" 2>/dev/null)"

  mkdir -p "$FLOWAI_WIKI_DIR"

  cat > "$report_file" <<REPORT
# FlowAI Knowledge Graph Report

> Built: ${built_at}
> Nodes: ${node_count} · Edges: ${edge_count} · Communities: ${community_count}
> Specs: ${spec_count} · Spec→Code edges: ${specifies_count}

---

## God Nodes

The highest-degree nodes in the graph — the architectural hubs everything
depends on. Start here when you don't know where to look.

${god_nodes:-_No nodes found. Run \`flowai graph build\` to populate._}

---

## Spec Coverage (Spec-Driven Development)

FlowAI uses Spec-Driven Development. Spec nodes carry higher trust than
regular source files — they are the **authoritative source of intent**.

**${spec_count} spec documents · ${specifies_count} spec→code edges · ${implements_count} code→spec (IMPLEMENTS) edges**

### Spec Status Dashboard

| Status | Count | Meaning |
|---|---|---|
| 🟢 implemented | ${cnt_implemented} | **Frontmatter** declares implemented (workflow / intent) |
| 🔵 in-progress  | ${cnt_inprogress} | Actively being implemented |
| ⬜ planned      | ${cnt_planned} | Accepted, not yet started |
| 🔴 deprecated   | ${cnt_deprecated} | No longer relevant |

> **SDD vs git:** Status here comes from spec YAML. **Git evidence** (commits that reference a spec ID) is compiled separately — see **Project evolution** below after \`flowai graph chronicle\`.

### Spec Inventory

${spec_nodes_list:-_No spec documents found in scan paths. Add specs to specs/ or .specify/._}

> [!TIP]
> Run \`flowai graph chronicle\` to mine git history for implementation evidence.
> Run \`flowai graph lint\` to detect gaps: unimplemented specs, unspecified code, zombie specs.

### Project evolution (compiled history)

Aligned with **persistent wiki** ideas: the graph stores a **denormalized timeline** on each spec node (\`evolution[]\`) and **IMPLEMENTS** edges from commits — so agents read \`graph.json\` / this report instead of re-walking \`git log\`.

| Metric | Value |
|---|---|
| Evolution events (total) | ${evo_event_total} |
| Specs with ≥1 git-linked event | ${specs_with_git_trail} |
| Code→spec IMPLEMENTS edges | ${implements_count} |

When these counts are non-zero, chronicle has linked **repository activity** to **spec IDs** (works for \`src/\`, \`lib/\`, \`internal/\`, \`apps/*\`, packages, etc. — any touched path except spec-only dirs). Reference IDs in commits, e.g. \`Implements UC-AUTH-001\`.

---

## Architectural Insights

Key design decisions and patterns extracted from source and documentation.
Treat **INFERRED** insights as hypotheses until verified.

${insights:-_No insights extracted yet. Run \`flowai graph ingest <spec-file>\` to populate._}

---

## Ambiguous Relationships

These relationships were flagged during extraction as uncertain.
They may reflect undocumented dependencies or extraction errors.

${ambiguous_edges:-_No ambiguous edges — clean graph._}

---

## Suggested Queries

These questions can be answered efficiently using this knowledge graph:

1. What are the core phases in the FlowAI pipeline and how do they signal each other?
2. Which modules does the AI tool dispatcher (\`ai.sh\`) depend on?
3. What does the skill resolution chain look like end-to-end?
4. Which specs have no corresponding implementation coverage?
5. Are there implementation divergences from existing spec documents?

---

## Community Structure

| Community | Description |
|---|---|
| god   | Central hubs with ≥10 edges — architectural load-bearers |
| hub   | Well-connected modules with 5-9 edges |
| leaf  | Peripheral files with <5 edges |

---

## Navigation Protocol

\`\`\`
GRAPH_REPORT.md  →  index.md  →  wiki/<topic>.md  →  graph.json  →  source files
\`\`\`

**For this project's SDD workflow:**
\`\`\`
Specs (.specify/, specs/)  ─ SPECIFIES edges ─►  Implementation (src/)
                            \`\`flowai graph lint\`\` detects divergence
\`\`\`

1. Read this file first for architectural orientation
2. Consult spec nodes for authoritative intent before touching source
3. Use \`index.md\` to find specific wiki pages by concept
4. Use \`graph.json\` for multi-hop dependency and spec-traceability queries
5. Only open raw source files for implementation details

---

_Generated by FlowAI graph engine. Run \`flowai graph update\` for an incremental refresh._
_Run \`flowai graph chronicle\` to mine git history for implementation evidence._
REPORT

  log_success "GRAPH_REPORT.md written"
}

# ─── index.md Generation ──────────────────────────────────────────────────────

_graph_generate_index() {
  local graph_file="$FLOWAI_GRAPH_JSON"
  local index_file="$FLOWAI_GRAPH_INDEX"
  [[ -f "$graph_file" ]] || return 1

  local built_at
  built_at="$(jq -r '.metadata.built_at' "$graph_file")"

  cat > "$index_file" <<INDEX
# Knowledge Graph — Content Index

> Updated: ${built_at}
> This file catalogs all nodes in the knowledge graph.
> Use it to find wiki pages before reading raw source files.

---

## Spec Documents (Authoritative Intent)

> Specs carry higher trust than source files. Check specs before implementation.

$(jq -r '
  .nodes |
  map(select(.type == "spec")) |
  sort_by(.label) |
  .[] |
  "- **[\(.label)](\(.path // .id))** " +
  "[" + (.status // "unknown") + "] " +
  (if .since != null then "· `" + .since + "` " else "" end) +
  (if .author != null then "· " + .author + " " else "" end) +
  "— " + ((.feature_ids // []) | if length > 0 then join(", ") else "no feature IDs" end)
' "$graph_file" 2>/dev/null || echo "_No spec documents found._")

---

## Source Files

$(jq -r '
  .nodes |
  map(select(.type == "file")) |
  sort_by(.label) |
  .[] |
  "- **[\(.label)](\(.path // .id))** — \(.summary // "source file")"
' "$graph_file" 2>/dev/null)

---

## Concepts

$(jq -r '
  .nodes |
  map(select(.type == "concept")) |
  sort_by(.label) |
  .[] |
  "- **\(.label)** — \(.summary // "")"
' "$graph_file" 2>/dev/null)

---

## Project Timeline

> Recent evolution (up to 12 events) — commits that reference spec IDs, compiled by \`flowai graph chronicle\`.
> Run \`flowai graph chronicle\` to populate. Format: date · spec · commit message

$(jq -r '
  [.nodes[] |
    select(.type == "spec" and (.evolution // []) != []) |
    . as $spec |
    (.evolution // []) |
    .[] |
    {date: .date, spec: $spec.label, message: .message, author: .author}
  ] |
  sort_by(.date) | reverse |
  .[0:12] |
  .[] |
  "- `\(.date)` **\(.spec)** — \(.message) _(\(.author))_"
' "$graph_file" 2>/dev/null || echo "_No evolution events yet. Run: flowai graph chronicle_")

---

_Run \`flowai graph update\` to refresh. Run \`flowai graph chronicle\` to mine git history._
INDEX

  log_success "index.md written"
}

# ─── Public API ───────────────────────────────────────────────────────────────

# Full graph build. force=true bypasses the SHA256 cache.
flowai_graph_build() {
  local force="${1:-false}"
  local scan_paths
  scan_paths="$(printf '%s' "$(_graph_scan_paths)" | tr '\n' ' ')"

  log_header "FlowAI Knowledge Graph — Build"
  log_info "Scan paths: ${scan_paths}"
  log_info "Wiki dir:   ${FLOWAI_WIKI_DIR}"

  mkdir -p "$FLOWAI_WIKI_DIR" "$FLOWAI_GRAPH_CACHE_DIR"

  # Pass 1: Structural
  local structural_file="${FLOWAI_GRAPH_CACHE_DIR}/structural.json"
  _graph_run_structural_pass "$force"

  # Pass 2: Semantic (optional — invokes configured AI; default off)
  if _graph_semantic_enabled; then
    mkdir -p "$FLOWAI_GRAPH_CACHE_DIR/semantic"
    _graph_run_semantic_pass "$force"
  fi

  # Merge + community detection
  _graph_merge "$structural_file"
  _graph_detect_communities

  # Pass 3: Frontmatter enrichment (pure bash, always runs, no LLM)
  # Reads spec frontmatter (status, since, author, affects) and ADR sections,
  # then patches the graph.json spec nodes in-place.
  if [[ -f "$FLOWAI_HOME/src/graph/chronicle.sh" ]]; then
    # shellcheck source=src/graph/chronicle.sh
    source "$FLOWAI_HOME/src/graph/chronicle.sh" 2>/dev/null || true
    _chronicle_enrich_spec_frontmatter 2>/dev/null || true
  fi

  # Read metadata for logging
  local node_count edge_count community_count
  node_count="$(jq '.metadata.node_count // 0' "$FLOWAI_GRAPH_JSON")"
  edge_count="$(jq '.metadata.edge_count // 0' "$FLOWAI_GRAPH_JSON")"
  community_count="$(jq '.metadata.community_count // 0' "$FLOWAI_GRAPH_JSON")"

  # Generate human-readable outputs
  _graph_generate_report
  _graph_generate_index

  flowai_graph_log_append "build" "nodes=${node_count} edges=${edge_count} communities=${community_count}"

  log_success "Knowledge graph built: ${node_count} nodes · ${edge_count} edges · ${community_count} communities"
  log_info "Report: ${FLOWAI_GRAPH_REPORT#$PWD/}"
  log_info "To enrich with git history run: flowai graph chronicle"
}

# Incremental update — only reprocesses files changed since last build.
flowai_graph_update() {
  log_header "FlowAI Knowledge Graph — Incremental Update"
  flowai_graph_build "false"
}

# ─── Status ───────────────────────────────────────────────────────────────────

flowai_graph_print_status() {
  if ! flowai_graph_exists; then
    printf '  %-14s %b%s%b\n' "Knowledge" "$YELLOW" "⚠  not built — run: flowai graph build" "$RESET"
    return
  fi

  local nodes edges communities age stale_label
  nodes="$(_flowai_graph_node_count)"
  edges="$(_flowai_graph_edge_count)"
  communities="$(_flowai_graph_community_count)"
  age="$(_flowai_graph_age_label)"

  # Spec coverage stats
  local spec_count implemented_count implements_edges
  spec_count="$(jq '.metadata.spec_count // 0' "$FLOWAI_GRAPH_JSON" 2>/dev/null || echo 0)"
  implemented_count="$(jq '[.nodes[] | select(.type=="spec" and .status=="implemented")] | length' \
    "$FLOWAI_GRAPH_JSON" 2>/dev/null || echo 0)"
  implements_edges="$(jq '.metadata.implements_edge_count // 0' "$FLOWAI_GRAPH_JSON" 2>/dev/null || echo 0)"

  if flowai_graph_is_stale; then
    stale_label=" (stale — run: flowai graph update)"
    printf '  %-14s %b%s%b\n' "Knowledge" "$YELLOW" "⚠  ${nodes} nodes · ${edges} edges · ${communities} communities · ${age}${stale_label}" "$RESET"
  else
    printf '  %-14s %b%s%b\n' "Knowledge" "$GREEN" "✓  ${nodes} nodes · ${edges} edges · ${communities} communities · built ${age}" "$RESET"
  fi

  if [[ "${spec_count:-0}" -gt 0 ]]; then
    printf '  %-14s %s\n' "SDD Coverage" "${implemented_count}/${spec_count} specs implemented · ${implements_edges} IMPLEMENTS edges"
  fi
}

