#!/usr/bin/env bash
# FlowAI — Knowledge Graph chronicle engine
#
# The Chronicle answers: "How did this project evolve? Why did things change?
# Which specs have git evidence of implementation?"
#
# Design principles (compact over complete):
#   - We do NOT create a node per git commit. That would bloat the graph.
#   - Instead, commits that reference spec IDs enrich the spec node itself
#     with an "evolution" timeline array
#   - YAML `id:` in frontmatter is merged into feature_ids during enrich so IDs
#     need not appear in the body (works across Spec Kit / ADR / RFC styles)
#   - IMPLEMENTS edges are created: file_node → spec_node when a commit touches
#     a file AND references a spec ID in its message
#   - ADR files get dedicated extraction: decision, status, consequences
#   - Output: enrichments are merged into graph.json via _graph_merge()
#
# Requires: git (checked at runtime, graceful fallback if absent)
#
# shellcheck shell=bash

# ─── Git Safety ───────────────────────────────────────────────────────────────

# Returns 0 if git is available and CWD is inside a git repo.
_chronicle_git_available() {
  command -v git >/dev/null 2>&1 || return 1
  git rev-parse --git-dir >/dev/null 2>&1 || return 1
}

# ─── Spec ID Pattern ─────────────────────────────────────────────────────────

# The canonical spec ID regex — same pattern used across build.sh and lint.sh.
# Matches: UC-XXX-NNN, FEAT-NNN, STORY-NNN, REQ-NNN, RFC-NNN, ADR-NNN, US-NNN
_SPEC_ID_PATTERN='\b(UC|FEAT|STORY|REQ|RFC|ADR|US)-[A-Z0-9_-]+'

# ─── Frontmatter Parsing ─────────────────────────────────────────────────────

# Parse YAML-like frontmatter from a spec/ADR file.
# Frontmatter is delimited by --- lines at the start of the file.
# Returns JSON: {id, status, since, author, affects, adr_status, superseded_by}
#
# Expected frontmatter format:
#   ---
#   id: UC-AUTH-001
#   status: implemented        # planned|in-progress|implemented|deprecated|superseded
#   since: 2026-03-15
#   author: michael
#   affects: src/commands/start.sh, src/core/auth.sh
#   adr_status: accepted       # for ADR files: draft|proposed|accepted|rejected|superseded
#   superseded_by: UC-AUTH-002 # optional
#   ---
_chronicle_parse_frontmatter() {
  local file="$1"

  # Check if file starts with ---
  local first_line
  first_line="$(head -1 "$file" 2>/dev/null)"
  if [[ "$first_line" != "---" ]]; then
    # No frontmatter — return empty object
    printf '{}'
    return 0
  fi

  # Extract frontmatter block (between first and second ---)
  local fm
  fm="$(awk '/^---$/{if(found){exit}else{found=1;next}} found{print}' "$file" 2>/dev/null)"

  # Parse each key: value pair
  local spec_id status since author affects adr_status superseded_by verified_by

  spec_id="$(printf '%s' "$fm" | grep -m1 '^id:' | sed 's/^id:[[:space:]]*//' | tr -d '[:space:]' || true)"
  status="$(printf '%s' "$fm" | grep -m1 '^status:' | sed 's/^status:[[:space:]]*//' | awk '{print $1}' || true)"
  since="$(printf '%s' "$fm" | grep -m1 '^since:' | sed 's/^since:[[:space:]]*//' | awk '{print $1}' || true)"
  author="$(printf '%s' "$fm" | grep -m1 '^author:' | sed 's/^author:[[:space:]]*//' | sed 's/[[:space:]]*#.*//' || true)"
  affects="$(printf '%s' "$fm" | grep -m1 '^affects:' | sed 's/^affects:[[:space:]]*//' | sed 's/[[:space:]]*#.*//' || true)"
  adr_status="$(printf '%s' "$fm" | grep -m1 '^adr_status:' | sed 's/^adr_status:[[:space:]]*//' | awk '{print $1}' || true)"
  superseded_by="$(printf '%s' "$fm" | grep -m1 '^superseded_by:' | sed 's/^superseded_by:[[:space:]]*//' | awk '{print $1}' || true)"
  verified_by="$(printf '%s' "$fm" | grep -m1 '^verified_by:' | sed 's/^verified_by:[[:space:]]*//' | awk '{print $1}' || true)"

  # Parse affects into JSON array (comma-separated paths)
  local affects_arr='[]'
  if [[ -n "$affects" ]]; then
    affects_arr="$(printf '%s' "$affects" | tr ',' '\n' | \
      sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | \
      jq -Rs 'split("\n") | map(select(. != ""))' 2>/dev/null || echo '[]')"
  fi

  jq -n \
    --arg id          "$spec_id" \
    --arg status      "$status" \
    --arg since       "$since" \
    --arg author      "$author" \
    --arg adr_status  "$adr_status" \
    --arg superseded  "$superseded_by" \
    --arg verified    "$verified_by" \
    --argjson affects "$affects_arr" \
    '{
      "frontmatter_id":  (if $id != "" then $id else null end),
      "status":          (if $status != "" then $status else null end),
      "since":           (if $since != "" then $since else null end),
      "author":          (if $author != "" then $author else null end),
      "adr_status":      (if $adr_status != "" then $adr_status else null end),
      "superseded_by":   (if $superseded != "" then $superseded else null end),
      "verified_by":     (if $verified != "" then $verified else null end),
      "affects":         $affects
    } | with_entries(select(.value != null))'
}

# ─── ADR Extraction ──────────────────────────────────────────────────────────

# Extract ADR-specific content sections (Decision, Status, Consequences).
# ADR files are a special subtype of spec with richer structured content.
_chronicle_extract_adr_sections() {
  local file="$1"

  # Extract ## Decision section
  local decision
  decision="$(awk '/^## [Dd]ecision/{found=1; next} found && /^## /{found=0} found{print}' \
    "$file" 2>/dev/null | head -5 | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g;s/  */ /g' || true)"

  # Extract ## Consequences / ## Context section
  local consequences
  consequences="$(awk '/^## [Cc]onsequences|^## [Cc]ontext/{found=1; next} found && /^## /{found=0} found{print}' \
    "$file" 2>/dev/null | head -5 | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' || true)"

  jq -n \
    --arg decision     "${decision:-}" \
    --arg consequences "${consequences:-}" \
    '{
      "decision":     (if $decision != "" then $decision else null end),
      "consequences": (if $consequences != "" then $consequences else null end)
    } | with_entries(select(.value != null))'
}

# ─── Git Log Mining ──────────────────────────────────────────────────────────

# Mine git log for commits that reference spec IDs.
# Returns only commits with spec ID references — compact, not full history.
# Output: JSONL, one JSON object per relevant commit:
#   {hash, date, author, message, spec_ids: [...], files_changed: [...]}
_chronicle_mine_git_log() {
  if ! _chronicle_git_available; then
    return 0
  fi

  local max_commits="${FLOWAI_CHRONICLE_MAX_COMMITS:-200}"

  git log \
    --format="%H|%ad|%ae|%s" \
    --date=short \
    --name-only \
    --diff-filter=AM \
    -n "$max_commits" \
    2>/dev/null | \
  awk '
    /^[0-9a-f]{40}\|/ {
      split($0, parts, "|")
      hash    = parts[1]
      date    = parts[2]
      author  = parts[3]
      message = parts[4]
      in_files = 1
      files = ""
      next
    }
    in_files && /^$/ {
      # End of file list for this commit — emit if message has spec IDs
      if (match(message, /(UC|FEAT|STORY|REQ|RFC|ADR|US)-[A-Z0-9_-]+/)) {
        print hash "|" date "|" author "|" message "|" files
      }
      in_files = 0
      files = ""
      next
    }
    in_files && !/^$/ {
      files = files (files == "" ? "" : ",") $0
      next
    }
  ' 2>/dev/null || true
}

# Extract all spec IDs from a string (commit message or file content).
_chronicle_extract_ids_from_str() {
  local str="$1"
  printf '%s' "$str" | grep -oE "$_SPEC_ID_PATTERN" | sort -u | \
    jq -Rs 'split("\n") | map(select(. != ""))' 2>/dev/null || echo '[]'
}

# ─── IMPLEMENTS Edge Generation ───────────────────────────────────────────────

# From the mined git log, generate IMPLEMENTS edges:
# For each commit that touches a file F and references spec ID S:
#   Edge: file_id(F) → spec_node_id_matching(S) with relation=IMPLEMENTS
#
# Also returns the evolution events to be merged into spec nodes.
#
# Writes two temp files:
#   $1: JSONL of IMPLEMENTS edges
#   $2: JSONL of spec evolution events {spec_id, event}
_chronicle_generate_edges() {
  local out_edges="$1"
  local out_evolution="$2"
  local graph_file="${FLOWAI_GRAPH_JSON}"

  [[ -f "$graph_file" ]] || return 0

  # Build a lookup: feature_id → spec node id
  # This maps "UC-AUTH-001" → "specs.auth-feature" (the actual graph node id)
  local lookup_tmp
  lookup_tmp="$(mktemp /tmp/flowai_chron_lookup.XXXXXX.json)"
  # First spec node wins when the same feature ID appears in multiple documents
  jq -r '
    .nodes |
    map(select(.type == "spec")) |
    map(. as $node | (.feature_ids // []) | map({key: ., value: $node.id})) |
    flatten |
    group_by(.key) |
    map(.[0]) |
    from_entries
  ' "$graph_file" 2>/dev/null > "$lookup_tmp" || printf '{}' > "$lookup_tmp"

  # Process each mined commit
  while IFS='|' read -r hash date author message files_csv; do
    [[ -z "$hash" ]] && continue

    # Extract spec IDs from this commit message
    local spec_ids_raw
    spec_ids_raw="$(printf '%s' "$message" | grep -oE "$_SPEC_ID_PATTERN" | sort -u || true)"
    [[ -z "$spec_ids_raw" ]] && continue

    # For each spec ID referenced in this commit:
    while IFS= read -r spec_id; do
      [[ -z "$spec_id" ]] && continue

      # Resolve spec ID to graph node ID
      local spec_node_id
      spec_node_id="$(jq -r --arg sid "$spec_id" '.[$sid] // empty' "$lookup_tmp" 2>/dev/null)"
      [[ -z "$spec_node_id" ]] && continue

      # Record evolution event on the spec node
      jq -cn \
        --arg spec_node "$spec_node_id" \
        --arg hash    "$hash" \
        --arg date    "$date" \
        --arg author  "$author" \
        --arg message "$message" \
        '{
          "spec_node_id": $spec_node,
          "event": {
            "hash":    $hash,
            "date":    $date,
            "author":  $author,
            "message": $message
          }
        }' >> "$out_evolution"

      # For each file touched in this commit: emit IMPLEMENTS edge
      IFS=',' read -ra touched_files <<< "$files_csv"
      for touched_file in "${touched_files[@]}"; do
        [[ -z "$touched_file" ]] && continue
        # Only link src/ files — not spec files linking to themselves
        [[ "$touched_file" == specs/* ]] && continue
        [[ "$touched_file" == .specify/* ]] && continue

        local file_node_id
        file_node_id="$(printf '%s' "$touched_file" | \
          tr '/' '.' | sed 's/\.\(sh\|md\|json\|js\|ts\|go\|py\|rb\)$//')"

        jq -cn \
          --arg src  "$file_node_id" \
          --arg tgt  "$spec_node_id" \
          --arg hash "$hash" \
          --arg date "$date" \
          '{
            "source":     $src,
            "target":     $tgt,
            "relation":   "IMPLEMENTS",
            "provenance": "EXTRACTED",
            "confidence": 0.9,
            "via_commit": $hash,
            "commit_date": $date
          }' >> "$out_edges"
      done

    done <<< "$spec_ids_raw"
  done < <(_chronicle_mine_git_log)

  rm -f "$lookup_tmp"
}

# ─── Merge Chronicle Enrichments Into Graph ───────────────────────────────────

# Apply evolution timelines and IMPLEMENTS edges into graph.json.
# This is additive — existing nodes are enriched, not replaced.
_chronicle_merge_into_graph() {
  local edges_file="$1"
  local evolution_file="$2"
  local graph_file="${FLOWAI_GRAPH_JSON}"

  [[ -f "$graph_file" ]] || return 0

  local updated
  updated="$(cat "$graph_file")"

  # 1. Merge IMPLEMENTS edges (deduplicate by source+target+relation)
  if [[ -s "$edges_file" ]]; then
    local new_edges
    new_edges="$(jq -sc '.' "$edges_file" 2>/dev/null || echo '[]')"
    updated="$(printf '%s' "$updated" | jq \
      --argjson new_edges "$new_edges" '
      .edges as $existing |
      ($existing + $new_edges) |
      unique_by({source: .source, target: .target, relation: .relation}) as $merged |
      . as $graph |
      $graph | .edges = $merged
    ' 2>/dev/null || printf '%s' "$updated")"
  fi

  # 2. Merge evolution events into spec nodes
  if [[ -s "$evolution_file" ]]; then
    # Group evolution events by spec_node_id
    local evolution_map
    evolution_map="$(jq -sc '
      group_by(.spec_node_id) |
      map({
        key: .[0].spec_node_id,
        value: (map(.event) | sort_by(.date))
      }) |
      from_entries
    ' "$evolution_file" 2>/dev/null || echo '{}')"

    updated="$(printf '%s' "$updated" | jq \
      --argjson evo "$evolution_map" '
      .nodes |= map(
        if .type == "spec" and ($evo[.id] != null) then
          . + {"evolution": ((.evolution // []) + $evo[.id] | unique_by(.hash))}
        else .
        end
      )
    ' 2>/dev/null || printf '%s' "$updated")"
  fi

  # 3. Update metadata (edge counts + evolution totals for agents / reports)
  updated="$(printf '%s' "$updated" | jq '
    .metadata.edge_count = (.edges | length) |
    .metadata.implements_edge_count = (.edges | map(select(.relation == "IMPLEMENTS")) | length) |
    .metadata.evolution_event_count = ([.nodes[] | (.evolution // []) | length] | add // 0) |
    .metadata.specs_with_git_activity = ([.nodes[] | select(.type == "spec" and ((.evolution // []) | length) > 0)] | length)
  ' 2>/dev/null || printf '%s' "$updated")"

  printf '%s' "$updated" > "$graph_file"
}

# ─── ADR Frontmatter Enrichment Pass ─────────────────────────────────────────

# Scan all spec nodes in the graph and enrich them with frontmatter fields.
# This runs after the structural pass — it reads frontmatter from disk and
# patches the already-inserted spec nodes in graph.json.
_chronicle_enrich_spec_frontmatter() {
  local graph_file="${FLOWAI_GRAPH_JSON}"
  [[ -f "$graph_file" ]] || return 0

  log_info "Enriching spec nodes with frontmatter..." >&2

  local tmp_graph
  tmp_graph="$(cat "$graph_file")"

  # For each spec node in the graph, find the source file and parse frontmatter
  local spec_paths
  spec_paths="$(printf '%s' "$tmp_graph" | jq -r '.nodes[] | select(.type == "spec") | .path // empty' 2>/dev/null)"

  while IFS= read -r rel_path; do
    [[ -z "$rel_path" ]] && continue
    local abs_path="$PWD/$rel_path"
    [[ -f "$abs_path" ]] || continue

    local fm
    fm="$(_chronicle_parse_frontmatter "$abs_path")"
    [[ -z "$fm" || "$fm" == '{}' ]] && continue

    # Is this an ADR file? (path or name-based)
    local base
    base="$(basename "$rel_path" | tr '[:upper:]' '[:lower:]')"
    local is_adr=false
    [[ "$rel_path" == docs/adr/* || "$rel_path" == docs/decisions/* || \
       "$base" == adr-*.md || "$base" == adr*.md ]] && is_adr=true

    local adr_sections='{}'
    if [[ "$is_adr" == "true" ]]; then
      adr_sections="$(_chronicle_extract_adr_sections "$abs_path")"
    fi

    # Make node_id from rel_path (same formula as structural pass)
    local node_id
    node_id="$(printf '%s' "$rel_path" | \
      tr '/' '.' | sed 's/\.\(sh\|md\|json\|js\|ts\)$//')"

    # Patch the graph node
    # Merge YAML `id:` into feature_ids so git chronicle can resolve IMPLEMENTS edges even when
    # the ID appears only in frontmatter (common in Spec Kit / ADR-style docs).
    tmp_graph="$(printf '%s' "$tmp_graph" | jq \
      --arg nid     "$node_id" \
      --argjson fm  "$fm" \
      --argjson adr "$adr_sections" \
      --argjson is_adr "$is_adr" '
      .nodes |= map(
        if .id == $nid then
          . +
          (if $fm.status != null        then {"status": $fm.status}               else {} end) +
          (if $fm.since != null         then {"since": $fm.since}                 else {} end) +
          (if $fm.author != null        then {"author": $fm.author}               else {} end) +
          (if $fm.adr_status != null    then {"adr_status": $fm.adr_status}       else {} end) +
          (if $fm.superseded_by != null then {"superseded_by": $fm.superseded_by} else {} end) +
          (if $fm.verified_by != null   then {"verified_by": $fm.verified_by}     else {} end) +
          (if ($fm.affects | length) > 0 then {"affects": $fm.affects}            else {} end) +
          (if $fm.frontmatter_id != null
              then {"feature_ids": ((.feature_ids // []) + [$fm.frontmatter_id] | unique)}
              else {}
           end) +
          (if $is_adr                   then {"subtype": "adr"}                   else {} end) +
          (if ($adr | keys | length) > 0 then $adr                              else {} end)
        else .
        end
      )
    ' 2>/dev/null || printf '%s' "$tmp_graph")"
  done <<< "$spec_paths"

  printf '%s' "$tmp_graph" > "$graph_file"
  log_success "Spec frontmatter enriched" >&2
}

# ─── Public API ───────────────────────────────────────────────────────────────

# Run the full chronicle pass:
#   1. Parse frontmatter on all spec nodes → enrich in-place
#   2. Mine git log for spec-referencing commits → IMPLEMENTS edges + evolution
#   3. Merge enrichments into graph.json
#   4. Update metadata
flowai_graph_chronicle() {
  local graph_file="${FLOWAI_GRAPH_JSON}"

  log_header "FlowAI Knowledge Graph — Chronicle"

  if [[ ! -f "$graph_file" ]]; then
    log_error "No graph.json found. Run: flowai graph build first."
    return 1
  fi

  # Step 1: Frontmatter enrichment (always runs)
  _chronicle_enrich_spec_frontmatter

  # Step 2: Git history mining (only if git is available)
  if ! _chronicle_git_available; then
    log_warn "git not available or not a git repo — skipping history mining"
    log_info "Commit-based IMPLEMENTS edges require a git repository."
    flowai_graph_log_append "chronicle" "frontmatter-only (no git)"
    log_success "Chronicle complete (frontmatter only)"
    return 0
  fi

  log_info "Mining git history for spec-referencing commits..."

  local tmp_edges tmp_evolution
  tmp_edges="$(mktemp /tmp/flowai_chron_edges.XXXXXX.jsonl)"
  tmp_evolution="$(mktemp /tmp/flowai_chron_evo.XXXXXX.jsonl)"

  _chronicle_generate_edges "$tmp_edges" "$tmp_evolution"

  local edge_count evo_count
  edge_count="$(wc -l < "$tmp_edges" | tr -d ' ')"
  evo_count="$(wc -l < "$tmp_evolution" | tr -d ' ')"

  log_info "Found: ${edge_count} IMPLEMENTS edges · ${evo_count} evolution events"

  if [[ "$edge_count" -gt 0 || "$evo_count" -gt 0 ]]; then
    log_info "Merging chronicle enrichments into graph.json..."
    _chronicle_merge_into_graph "$tmp_edges" "$tmp_evolution"
    log_success "Graph enriched: +${edge_count} IMPLEMENTS edges"
  else
    log_info "No spec-referencing commits found in history (last ${FLOWAI_CHRONICLE_MAX_COMMITS:-200} commits)"
    log_info "Tip: Reference spec IDs in commit messages, e.g.: 'Implements UC-AUTH-001'"
  fi

  rm -f "$tmp_edges" "$tmp_evolution"

  # Regenerate report and index with updated data
  source "$FLOWAI_HOME/src/graph/build.sh" 2>/dev/null || true
  _graph_generate_report 2>/dev/null || true
  _graph_generate_index  2>/dev/null || true

  flowai_graph_log_append "chronicle" "implements=${edge_count} evolution_events=${evo_count}"
  log_success "Chronicle complete"
}
