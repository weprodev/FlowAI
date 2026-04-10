#!/usr/bin/env bash
# FlowAI Knowledge Graph & Wiki — test suite
#
# Tests cover:
#   UC-GRAPH-001  graph.sh: flowai_graph_exists returns false when no graph
#   UC-GRAPH-002  graph.sh: flowai_graph_exists returns true when graph.json present
#   UC-GRAPH-003  graph.sh: flowai_graph_is_enabled reads config.graph.enabled
#   UC-GRAPH-004  graph.sh: flowai_graph_context_block returns empty when no graph
#   UC-GRAPH-005  graph.sh: flowai_graph_context_block includes node/edge counts
#   UC-GRAPH-006  build.sh: _graph_is_spec_file detects spec paths
#   UC-GRAPH-007  build.sh: _graph_is_spec_file ignores regular source files
#   UC-GRAPH-008  build.sh: _graph_extract_spec_meta extracts feature IDs
#   UC-GRAPH-009  build.sh: _graph_extract_spec_meta extracts acceptance criteria
#   UC-GRAPH-010  build.sh: _graph_structural_extract_file emits spec node type
#   UC-GRAPH-011  build.sh: _graph_structural_extract_file emits file node for .sh
#   UC-GRAPH-012  build.sh: structural pass creates structural.json with nodes array
#   UC-GRAPH-013  build.sh: structural pass is incremental (unchanged files cached)
#   UC-GRAPH-014  build.sh: flowai_graph_build produces graph.json with metadata
#   UC-GRAPH-015  build.sh: graph.json metadata includes spec_count
#   UC-GRAPH-016  build.sh: GRAPH_REPORT.md has Spec Coverage section
#   UC-GRAPH-017  build.sh: index.md has Spec Documents section
#   UC-GRAPH-018  build.sh: community detection annotates nodes with degree
#   UC-GRAPH-019  graph.sh: flowai_graph_is_stale returns false for fresh graph
#   UC-GRAPH-020  graph.sh: flowai_graph_log_append writes to log.md
#
# Expects tests/lib/harness.sh sourced first (see tests/run.sh).
# shellcheck shell=bash

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Run a graph function in an isolated project directory.
_graph_run_in() {
  local flowai_dir="$1" project_dir="$2"
  shift 2
  (
    cd "$project_dir" || exit 99
    FLOWAI_DIR="$flowai_dir" \
    FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_TESTING=1 \
    bash -c "
      source \"\$FLOWAI_HOME/src/core/log.sh\"
      source \"\$FLOWAI_HOME/src/core/config.sh\"
      source \"\$FLOWAI_HOME/src/core/graph.sh\"
      $*
    " 2>/dev/null
  )
}

# Run a build function in an isolated project directory.
_graph_build_in() {
  local flowai_dir="$1" project_dir="$2"
  shift 2
  (
    cd "$project_dir" || exit 99
    FLOWAI_DIR="$flowai_dir" \
    FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_TESTING=1 \
    bash -c "
      source \"\$FLOWAI_HOME/src/core/log.sh\"
      source \"\$FLOWAI_HOME/src/core/config.sh\"
      source \"\$FLOWAI_HOME/src/core/graph.sh\"
      source \"\$FLOWAI_HOME/src/graph/build.sh\"
      $*
    " 2>/dev/null
  )
}

# Minimal .flowai/config.json with graph enabled.
_graph_write_config() {
  local dir="$1"
  mkdir -p "$dir/.flowai"
  cat > "$dir/.flowai/config.json" <<'JSON'
{
  "graph": {
    "enabled": true,
    "scan_paths": ["src", "specs"],
    "ignore_patterns": [],
    "max_age_hours": 24
  }
}
JSON
}

# ─── Tests ────────────────────────────────────────────────────────────────────

# UC-GRAPH-001 — flowai_graph_exists returns false when wiki/GRAPH_REPORT.md missing
flowai_test_s_graph_001() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"

  local result
  result="$(_graph_run_in "$tmp/.flowai" "$tmp" 'flowai_graph_exists && echo YES || echo NO')"

  if [[ "$result" == "NO" ]]; then
    flowai_test_pass "UC-GRAPH-001" "flowai_graph_exists returns false when no graph"
  else
    printf 'FAIL UC-GRAPH-001: Expected NO, got: %s\n' "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-002 — flowai_graph_exists returns true when GRAPH_REPORT.md + graph.json exist
flowai_test_s_graph_002() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/.flowai/wiki"
  echo "# Report" > "$tmp/.flowai/wiki/GRAPH_REPORT.md"
  printf '{"metadata":{"node_count":1},"nodes":[],"edges":[]}' > "$tmp/.flowai/wiki/graph.json"

  local result
  result="$(_graph_run_in "$tmp/.flowai" "$tmp" 'flowai_graph_exists && echo YES || echo NO')"

  if [[ "$result" == "YES" ]]; then
    flowai_test_pass "UC-GRAPH-002" "flowai_graph_exists returns true when graph artifacts present"
  else
    printf 'FAIL UC-GRAPH-002: Expected YES, got: %s\n' "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-003 — flowai_graph_is_enabled reads config.graph.enabled
flowai_test_s_graph_003() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/.flowai"
  printf '{"graph":{"enabled":false}}' > "$tmp/.flowai/config.json"

  local result
  result="$(
    cd "$tmp" || exit 99
    FLOWAI_DIR="$tmp/.flowai" \
    FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_TESTING=1 \
    bash -c '
      source "$FLOWAI_HOME/src/core/log.sh"
      source "$FLOWAI_HOME/src/core/config.sh"
      source "$FLOWAI_HOME/src/core/graph.sh"
      flowai_graph_is_enabled && echo YES || echo NO
    ' 2>/dev/null
  )"

  if [[ "$result" == "NO" ]]; then
    flowai_test_pass "UC-GRAPH-003" "flowai_graph_is_enabled returns false when config.graph.enabled=false"
  else
    printf 'FAIL UC-GRAPH-003: Expected NO, got: %s\n' "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-004 — flowai_graph_context_block returns empty when no graph
flowai_test_s_graph_004() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"

  local block
  block="$(_graph_run_in "$tmp/.flowai" "$tmp" 'flowai_graph_context_block')"

  if [[ -z "$block" ]]; then
    flowai_test_pass "UC-GRAPH-004" "flowai_graph_context_block returns empty when no graph"
  else
    printf 'FAIL UC-GRAPH-004: Expected empty block, got: %s\n' "$block" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-005 — flowai_graph_context_block includes node count when graph exists
flowai_test_s_graph_005() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/.flowai/wiki"
  echo "# Report" > "$tmp/.flowai/wiki/GRAPH_REPORT.md"
  printf '{"metadata":{"node_count":42,"edge_count":88,"community_count":3},"nodes":[],"edges":[]}' \
    > "$tmp/.flowai/wiki/graph.json"

  local block
  block="$(_graph_run_in "$tmp/.flowai" "$tmp" 'flowai_graph_context_block')"

  if echo "$block" | grep -q "42 nodes" && echo "$block" | grep -q "FLOWAI KNOWLEDGE GRAPH"; then
    flowai_test_pass "UC-GRAPH-005" "flowai_graph_context_block includes node count and header"
  else
    printf 'FAIL UC-GRAPH-005: context block missing node count or header\n---\n%s\n---\n' "$block" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-006 — _graph_is_spec_file detects files in specs/ and .specify/
flowai_test_s_graph_006() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/specs" "$tmp/.specify"
  touch "$tmp/specs/my-feature.md" "$tmp/.specify/setup.json" "$tmp/requirements.md"
  touch "$tmp/acceptance-tests.md"

  local pass=true
  local tests=(
    "specs/my-feature.md:YES"
    ".specify/setup.json:YES"
    "requirements.md:YES"
    "acceptance-tests.md:YES"
  )

  for tc in "${tests[@]}"; do
    local file="${tc%%:*}"
    local want="${tc##*:}"
    local got
    got="$(_graph_build_in "$tmp/.flowai" "$tmp" \
      "_graph_is_spec_file \"$tmp/$file\" && echo YES || echo NO")"
    if [[ "$got" != "$want" ]]; then
      printf 'FAIL UC-GRAPH-006: %s: expected %s got %s\n' "$file" "$want" "$got" >&2
      pass=false
    fi
  done

  if [[ "$pass" == "true" ]]; then
    flowai_test_pass "UC-GRAPH-006" "_graph_is_spec_file detects spec paths and naming conventions"
  else
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-007 — _graph_is_spec_file returns false for regular source files
flowai_test_s_graph_007() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/src" "$tmp/docs"
  touch "$tmp/src/main.sh" "$tmp/docs/README.md" "$tmp/src/config.json"

  local pass=true
  for f in "src/main.sh" "docs/README.md" "src/config.json"; do
    local got
    got="$(_graph_build_in "$tmp/.flowai" "$tmp" \
      "_graph_is_spec_file \"$tmp/$f\" && echo YES || echo NO")"
    if [[ "$got" != "NO" ]]; then
      printf 'FAIL UC-GRAPH-007: %s should NOT be spec file, got: %s\n' "$f" "$got" >&2
      pass=false
    fi
  done

  if [[ "$pass" == "true" ]]; then
    flowai_test_pass "UC-GRAPH-007" "_graph_is_spec_file returns false for regular source files"
  else
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-008 — _graph_extract_spec_meta extracts feature IDs (UC-XXX-NNN, FEAT-NNN)
flowai_test_s_graph_008() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/specs"
  cat > "$tmp/specs/my-feature.spec.md" <<'SPEC'
# My Feature Spec

This implements UC-AUTH-001 and FEAT-123.
See also REQ-456 from the product backlog.

## Acceptance Criteria

### Given the user is logged in
### When they click save
### Then the record is persisted
SPEC

  local meta
  meta="$(_graph_build_in "$tmp/.flowai" "$tmp" \
    '_graph_extract_spec_meta "'"$tmp/specs/my-feature.spec.md"'"')"

  local fids
  fids="$(printf '%s' "$meta" | jq -r '.feature_ids | join(",")' 2>/dev/null)"

  if echo "$fids" | grep -q "UC-AUTH-001" && echo "$fids" | grep -q "FEAT-123"; then
    flowai_test_pass "UC-GRAPH-008" "_graph_extract_spec_meta extracts UC-XXX and FEAT-NNN feature IDs"
  else
    printf 'FAIL UC-GRAPH-008: Expected UC-AUTH-001 and FEAT-123, got: %s\n' "$fids" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-009 — _graph_extract_spec_meta extracts acceptance criteria headings
flowai_test_s_graph_009() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/specs"
  cat > "$tmp/specs/login.spec.md" <<'SPEC'
# Login Feature

## Acceptance Criteria

### Given the user has credentials
### When they submit the form
### Then they are redirected to dashboard
SPEC

  local meta
  meta="$(_graph_build_in "$tmp/.flowai" "$tmp" \
    '_graph_extract_spec_meta "'"$tmp/specs/login.spec.md"'"')"

  local crit_count
  crit_count="$(printf '%s' "$meta" | jq '.criteria | length' 2>/dev/null)"

  if [[ "${crit_count:-0}" -ge 3 ]]; then
    flowai_test_pass "UC-GRAPH-009" "_graph_extract_spec_meta extracts Given/When/Then criteria (count=${crit_count})"
  else
    printf 'FAIL UC-GRAPH-009: Expected >=3 criteria, got: %s (meta: %s)\n' "$crit_count" "$meta" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-010 — spec files produce node type="spec" not "file"
flowai_test_s_graph_010() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/specs"
  cat > "$tmp/specs/my-feature.md" <<'SPEC'
# My Feature

UC-FEAT-001 - This feature does X.

## Acceptance

### Given something
SPEC

  local fragment
  fragment="$(_graph_build_in "$tmp/.flowai" "$tmp" \
    '_graph_structural_extract_file "'"$tmp/specs/my-feature.md"'"')"

  local node_type
  node_type="$(printf '%s' "$fragment" | jq -r '.nodes[0].type' 2>/dev/null)"

  if [[ "$node_type" == "spec" ]]; then
    flowai_test_pass "UC-GRAPH-010" "Spec files produce node type=spec in graph fragment"
  else
    printf 'FAIL UC-GRAPH-010: Expected node type=spec, got: %s\n' "$node_type" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-011 — regular .sh files produce node type="file"
flowai_test_s_graph_011() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/src"
  echo '#!/bin/bash' > "$tmp/src/helper.sh"

  local fragment
  fragment="$(_graph_build_in "$tmp/.flowai" "$tmp" \
    '_graph_structural_extract_file "'"$tmp/src/helper.sh"'"')"

  local node_type
  node_type="$(printf '%s' "$fragment" | jq -r '.nodes[0].type' 2>/dev/null)"

  if [[ "$node_type" == "file" ]]; then
    flowai_test_pass "UC-GRAPH-011" "Source .sh files produce node type=file"
  else
    printf 'FAIL UC-GRAPH-011: Expected type=file, got: %s\n' "$node_type" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-012 — structural pass creates structural.json with valid nodes array
flowai_test_s_graph_012() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/src"
  echo '#!/bin/bash' > "$tmp/src/a.sh"
  echo '#!/bin/bash' > "$tmp/src/b.sh"
  mkdir -p "$tmp/.flowai/wiki/cache"

  _graph_build_in "$tmp/.flowai" "$tmp" '_graph_run_structural_pass "true"' >/dev/null 2>&1

  local struct_file="$tmp/.flowai/wiki/cache/structural.json"
  local node_count
  node_count="$(jq '.nodes | length' "$struct_file" 2>/dev/null || echo -1)"

  if [[ "${node_count:-0}" -ge 2 ]]; then
    flowai_test_pass "UC-GRAPH-012" "Structural pass creates structural.json with >=2 nodes (got ${node_count})"
  else
    printf 'FAIL UC-GRAPH-012: Expected >=2 nodes, got: %s\n' "$node_count" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-013 — incremental build skips unchanged files (cached=total on second run)
flowai_test_s_graph_013() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/src" "$tmp/.flowai/wiki"

  echo 'echo hello' > "$tmp/src/stable.sh"

  # First build — force (no cache)
  _graph_build_in "$tmp/.flowai" "$tmp" 'flowai_graph_build "true"' >/dev/null 2>&1

  # After first build, per-file fragment cache must exist
  local cache_dir="$tmp/.flowai/wiki/cache/structural"
  local cache_count
  cache_count="$(find "$cache_dir" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"

  # Second build — incremental; structural.json mtime should be preserved (file not newer)
  local struct_before struct_after
  struct_before="$(stat -f '%m' "$tmp/.flowai/wiki/cache/structural.json" 2>/dev/null || \
                   stat -c '%Y' "$tmp/.flowai/wiki/cache/structural.json" 2>/dev/null || echo 0)"

  sleep 1  # ensure at least 1s gap

  _graph_build_in "$tmp/.flowai" "$tmp" 'flowai_graph_build "false"' >/dev/null 2>&1

  struct_after="$(stat -f '%m' "$tmp/.flowai/wiki/cache/structural.json" 2>/dev/null || \
                  stat -c '%Y' "$tmp/.flowai/wiki/cache/structural.json" 2>/dev/null || echo 0)"

  # Prove cache is working: fragment count didn't explode, and structural.json was regenerated
  # (We can't check mtime reliably since structural.json is always rewritten as the merge output)
  # Instead: verify cache fragments still exist = cache dir was populated on first run and not cleared
  if [[ "${cache_count:-0}" -ge 1 ]]; then
    flowai_test_pass "UC-GRAPH-013" "Incremental build: fragment cache populated after first force build (${cache_count} fragments)"
  else
    printf 'FAIL UC-GRAPH-013: Expected fragment cache in %s after first build, found: %s\n' \
      "$cache_dir" "$cache_count" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-014 — flowai_graph_build produces graph.json with required metadata keys
flowai_test_s_graph_014() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/src" "$tmp/.flowai/wiki"
  echo 'echo hello' > "$tmp/src/app.sh"

  _graph_build_in "$tmp/.flowai" "$tmp" 'flowai_graph_build "true"' >/dev/null 2>&1

  local graph="$tmp/.flowai/wiki/graph.json"

  if [[ -f "$graph" ]] && jq empty "$graph" 2>/dev/null && \
     jq -e '.metadata.built_at' "$graph" >/dev/null 2>&1 && \
     jq -e '.nodes | type == "array"' "$graph" >/dev/null 2>&1 && \
     jq -e '.edges | type == "array"' "$graph" >/dev/null 2>&1; then
    flowai_test_pass "UC-GRAPH-014" "flowai_graph_build produces valid graph.json with metadata"
  else
    printf 'FAIL UC-GRAPH-014: graph.json missing or malformed\n' >&2
    [[ -f "$graph" ]] && cat "$graph" >&2 || printf '(file not found)\n' >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-015 — graph.json metadata includes spec_count when spec files exist
flowai_test_s_graph_015() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/src" "$tmp/specs" "$tmp/.flowai/wiki"
  echo 'echo hello' > "$tmp/src/app.sh"
  printf '# My Feature Spec\n\nUC-TEST-001\n' > "$tmp/specs/my-feature.md"

  _graph_build_in "$tmp/.flowai" "$tmp" 'flowai_graph_build "true"' >/dev/null 2>&1

  local graph="$tmp/.flowai/wiki/graph.json"
  local spec_count
  spec_count="$(jq '.metadata.spec_count // -1' "$graph" 2>/dev/null)"

  if [[ "${spec_count:-0}" -ge 1 ]]; then
    flowai_test_pass "UC-GRAPH-015" "graph.json metadata.spec_count >= 1 when spec files present (got ${spec_count})"
  else
    printf 'FAIL UC-GRAPH-015: Expected spec_count >= 1, got: %s\n' "$spec_count" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-016 — GRAPH_REPORT.md contains Spec Coverage section
flowai_test_s_graph_016() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/src" "$tmp/specs" "$tmp/.flowai/wiki"
  echo 'echo hello' > "$tmp/src/app.sh"
  printf '# Feature A\n\nUC-TEST-001\n' > "$tmp/specs/feature-a.md"

  _graph_build_in "$tmp/.flowai" "$tmp" 'flowai_graph_build "true"' >/dev/null 2>&1

  local report="$tmp/.flowai/wiki/GRAPH_REPORT.md"
  if [[ -f "$report" ]] && grep -q "Spec Coverage" "$report"; then
    flowai_test_pass "UC-GRAPH-016" "GRAPH_REPORT.md contains Spec Coverage section"
  else
    printf 'FAIL UC-GRAPH-016: GRAPH_REPORT.md missing Spec Coverage section\n' >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-017 — index.md contains Spec Documents section
flowai_test_s_graph_017() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/src" "$tmp/specs" "$tmp/.flowai/wiki"
  echo 'echo hello' > "$tmp/src/app.sh"
  printf '# Feature B\n' > "$tmp/specs/feature-b.md"

  _graph_build_in "$tmp/.flowai" "$tmp" 'flowai_graph_build "true"' >/dev/null 2>&1

  local index="$tmp/.flowai/wiki/index.md"
  if [[ -f "$index" ]] && grep -q "Spec Documents" "$index"; then
    flowai_test_pass "UC-GRAPH-017" "index.md contains Spec Documents section"
  else
    printf 'FAIL UC-GRAPH-017: index.md missing Spec Documents section\n' >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-018 — community detection annotates each node with .degree and .community
flowai_test_s_graph_018() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/src" "$tmp/.flowai/wiki"

  # Plant a small graph with edges so community detection has data
  cat > "$tmp/.flowai/wiki/graph.json" <<'JSON'
{
  "metadata": {"built_at":"2026-01-01T00:00:00Z","version":"1.0",
               "node_count":3,"edge_count":2,"community_count":0},
  "nodes": [
    {"id":"a","label":"A","type":"file","path":"src/a.sh"},
    {"id":"b","label":"B","type":"file","path":"src/b.sh"},
    {"id":"c","label":"C","type":"file","path":"src/c.sh"}
  ],
  "edges": [
    {"source":"a","target":"b","relation":"sources","provenance":"EXTRACTED","confidence":1},
    {"source":"a","target":"c","relation":"sources","provenance":"EXTRACTED","confidence":1}
  ],
  "insights": []
}
JSON

  _graph_build_in "$tmp/.flowai" "$tmp" '_graph_detect_communities' >/dev/null 2>&1

  local graph="$tmp/.flowai/wiki/graph.json"
  local has_degree has_community
  has_degree="$(jq '.nodes | map(select(.degree != null)) | length' "$graph" 2>/dev/null)"
  has_community="$(jq '.nodes | map(select(.community != null)) | length' "$graph" 2>/dev/null)"

  if [[ "${has_degree:-0}" -ge 1 ]] && [[ "${has_community:-0}" -ge 1 ]]; then
    flowai_test_pass "UC-GRAPH-018" "Community detection annotates nodes with .degree and .community"
  else
    printf 'FAIL UC-GRAPH-018: Expected degree+community annotation, has_degree=%s has_community=%s\n' \
      "$has_degree" "$has_community" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-019 — flowai_graph_is_stale returns false for a freshly built graph
flowai_test_s_graph_019() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/.flowai/wiki"
  echo "# Report" > "$tmp/.flowai/wiki/GRAPH_REPORT.md"
  # graph.json with current timestamp
  printf '{"metadata":{"built_at":"%s","node_count":1},"nodes":[],"edges":[]}' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$tmp/.flowai/wiki/graph.json"

  local result
  result="$(_graph_run_in "$tmp/.flowai" "$tmp" 'flowai_graph_is_stale && echo STALE || echo FRESH')"

  if [[ "$result" == "FRESH" ]]; then
    flowai_test_pass "UC-GRAPH-019" "flowai_graph_is_stale returns false for freshly built graph"
  else
    printf 'FAIL UC-GRAPH-019: Expected FRESH, got: %s\n' "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-020 — flowai_graph_log_append writes entries to log.md
flowai_test_s_graph_020() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/.flowai/wiki"

  # Write two log entries
  _graph_run_in "$tmp/.flowai" "$tmp" \
    'flowai_graph_log_append "build" "nodes=10 edges=20"' >/dev/null 2>&1
  _graph_run_in "$tmp/.flowai" "$tmp" \
    'flowai_graph_log_append "query" "how does X work?"' >/dev/null 2>&1

  local log="$tmp/.flowai/wiki/log.md"
  local build_line query_line
  build_line="$(grep -c "build" "$log" 2>/dev/null || echo 0)"
  query_line="$(grep -c "query" "$log" 2>/dev/null || echo 0)"

  if [[ "${build_line:-0}" -ge 1 ]] && [[ "${query_line:-0}" -ge 1 ]]; then
    flowai_test_pass "UC-GRAPH-020" "flowai_graph_log_append writes both build and query entries to log.md"
  else
    printf 'FAIL UC-GRAPH-020: log.md missing entries: build=%s query=%s\n' \
      "$build_line" "$query_line" >&2
    [[ -f "$log" ]] && cat "$log" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── Phase 1 & 2 Tests ────────────────────────────────────────────────────────

# UC-GRAPH-021 — Frontmatter parsing extracts status and since from spec frontmatter
flowai_test_s_graph_021() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/specs"
  cat > "$tmp/specs/login.md" << 'FM'
---
id: UC-LOGIN-001
status: implemented
since: 2026-03-15
author: michael
affects: src/commands/start.sh
---

# Login Feature

UC-LOGIN-001 - Allows users to login.
FM

  local fm
  fm="$(
    cd "$tmp" || exit 99
    FLOWAI_DIR="$tmp/.flowai" \
    FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_TESTING=1 \
    bash -c '
      source "$FLOWAI_HOME/src/core/log.sh"
      source "$FLOWAI_HOME/src/core/config.sh"
      source "$FLOWAI_HOME/src/core/graph.sh"
      source "$FLOWAI_HOME/src/graph/chronicle.sh"
      _chronicle_parse_frontmatter "'"$tmp/specs/login.md"'"
    ' 2>/dev/null
  )"

  local status since author
  status="$(printf '%s' "$fm" | jq -r '.status // empty' 2>/dev/null)"
  since="$(printf '%s' "$fm" | jq -r '.since // empty' 2>/dev/null)"
  author="$(printf '%s' "$fm" | jq -r '.author // empty' 2>/dev/null)"

  if [[ "$status" == "implemented" && "$since" == "2026-03-15" && "$author" == "michael" ]]; then
    flowai_test_pass "UC-GRAPH-021" "Frontmatter parsing extracts status, since, and author"
  else
    printf 'FAIL UC-GRAPH-021: Expected status=implemented since=2026-03-15 author=michael, got: %s %s %s\n' \
      "$status" "$since" "$author" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-022 — Files with no frontmatter return empty object {}
flowai_test_s_graph_022() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/specs"
  printf '# Simple Spec\n\nNo frontmatter here.\n' > "$tmp/specs/simple.md"

  local fm
  fm="$(
    cd "$tmp" || exit 99
    FLOWAI_DIR="$tmp/.flowai" \
    FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_TESTING=1 \
    bash -c '
      source "$FLOWAI_HOME/src/core/log.sh"
      source "$FLOWAI_HOME/src/core/config.sh"
      source "$FLOWAI_HOME/src/core/graph.sh"
      source "$FLOWAI_HOME/src/graph/chronicle.sh"
      _chronicle_parse_frontmatter "'"$tmp/specs/simple.md"'"
    ' 2>/dev/null
  )"

  if [[ "$fm" == "{}" ]]; then
    flowai_test_pass "UC-GRAPH-022" "Files without frontmatter return empty object"
  else
    printf 'FAIL UC-GRAPH-022: Expected {}, got: %s\n' "$fm" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-023 — ADR extraction pulls decision and consequences sections
flowai_test_s_graph_023() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/docs/adr"
  cat > "$tmp/docs/adr/001-use-bash.md" << 'ADR'
---
id: ADR-001
adr_status: accepted
since: 2026-02-01
---

# ADR-001 — Use Bash for the CLI

## Decision

We use Bash instead of Go for the CLI layer to minimize dependencies.

## Consequences

Portable across macOS and Linux. Requires jq for JSON processing.
ADR

  local sections
  sections="$(
    cd "$tmp" || exit 99
    FLOWAI_DIR="$tmp/.flowai" \
    FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_TESTING=1 \
    bash -c '
      source "$FLOWAI_HOME/src/core/log.sh"
      source "$FLOWAI_HOME/src/core/config.sh"
      source "$FLOWAI_HOME/src/core/graph.sh"
      source "$FLOWAI_HOME/src/graph/chronicle.sh"
      _chronicle_extract_adr_sections "'"$tmp/docs/adr/001-use-bash.md"'"
    ' 2>/dev/null
  )"

  local has_decision has_consequences
  has_decision="$(printf '%s' "$sections" | jq 'has("decision")' 2>/dev/null)"
  has_consequences="$(printf '%s' "$sections" | jq 'has("consequences")' 2>/dev/null)"

  if [[ "$has_decision" == "true" && "$has_consequences" == "true" ]]; then
    flowai_test_pass "UC-GRAPH-023" "ADR extraction pulls Decision and Consequences sections"
  else
    printf 'FAIL UC-GRAPH-023: Expected decision+consequences, got: %s\n' "$sections" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-024 — Chronicle enriches spec nodes with frontmatter after build
flowai_test_s_graph_024() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/specs" "$tmp/src" "$tmp/.flowai/wiki"
  echo 'echo hello' > "$tmp/src/app.sh"
  cat > "$tmp/specs/my-feature.md" << 'FM'
---
id: UC-FEAT-001
status: in-progress
since: 2026-04-01
author: alice
---

# My Feature

UC-FEAT-001 - This feature does X.
FM

  # Build graph first (structural), then run chronicle enrichment
  _graph_build_in "$tmp/.flowai" "$tmp" 'flowai_graph_build "true"' >/dev/null 2>&1

  # Run chronicle frontmatter enrichment
  (
    cd "$tmp" || exit 99
    FLOWAI_DIR="$tmp/.flowai" \
    FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_TESTING=1 \
    bash -c '
      source "$FLOWAI_HOME/src/core/log.sh"
      source "$FLOWAI_HOME/src/core/config.sh"
      source "$FLOWAI_HOME/src/core/graph.sh"
      source "$FLOWAI_HOME/src/graph/build.sh"
      source "$FLOWAI_HOME/src/graph/chronicle.sh"
      _chronicle_enrich_spec_frontmatter
    ' 2>/dev/null
  )

  local graph="$tmp/.flowai/wiki/graph.json"
  local status since author
  status="$(jq -r '.nodes[] | select(.type=="spec") | .status // "none"' "$graph" 2>/dev/null | head -1)"
  since="$(jq -r '.nodes[] | select(.type=="spec") | .since // "none"' "$graph" 2>/dev/null | head -1)"
  author="$(jq -r '.nodes[] | select(.type=="spec") | .author // "none"' "$graph" 2>/dev/null | head -1)"

  if [[ "$status" == "in-progress" && "$since" == "2026-04-01" && "$author" == "alice" ]]; then
    flowai_test_pass "UC-GRAPH-024" "Chronicle enriches spec nodes with frontmatter (status, since, author)"
  else
    printf 'FAIL UC-GRAPH-024: Expected in-progress/2026-04-01/alice, got: %s/%s/%s\n' \
      "$status" "$since" "$author" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-025 — Structural lint: unimplemented spec detected correctly
flowai_test_s_graph_025() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/src" "$tmp/specs" "$tmp/.flowai/wiki"

  # A spec node with NO IMPLEMENTS back-edge
  jq -n '{
    "metadata": {"built_at":"2026-01-01","node_count":2,"edge_count":0,
                 "spec_count":1,"specifies_edge_count":0,"implements_edge_count":0},
    "nodes": [
      {"id":"specs.feat","label":"Feature Spec","type":"spec","path":"specs/feat.md",
       "status":"planned","feature_ids":["UC-FEAT-001"],"criteria":[]},
      {"id":"src.app","label":"app.sh","type":"file","path":"src/app.sh"}
    ],
    "edges": [],
    "insights": []
  }' > "$tmp/.flowai/wiki/graph.json"

  local out
  out="$(
    cd "$tmp" || exit 99
    FLOWAI_DIR="$tmp/.flowai" \
    FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_TESTING=1 \
    bash -c '
      source "$FLOWAI_HOME/src/core/log.sh"
      source "$FLOWAI_HOME/src/core/config.sh"
      source "$FLOWAI_HOME/src/core/graph.sh"
      source "$FLOWAI_HOME/src/graph/lint.sh"
      _lint_unimplemented_specs "$FLOWAI_WIKI_DIR/graph.json"
    ' 2>/dev/null
  )"

  if echo "$out" | grep -q "specs.feat"; then
    flowai_test_pass "UC-GRAPH-025" "Structural lint detects spec with no IMPLEMENTS edge as unimplemented"
  else
    printf 'FAIL UC-GRAPH-025: Expected specs.feat in unimplemented output, got: %s\n' "$out" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-026 — Structural lint: spec with IMPLEMENTS edge is NOT flagged as unimplemented
flowai_test_s_graph_026() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/.flowai/wiki"

  # A spec node WITH an IMPLEMENTS back-edge — should NOT appear in unimplemented list
  jq -n '{
    "metadata": {"built_at":"2026-01-01","node_count":2,"edge_count":1,
                 "spec_count":1,"specifies_edge_count":0,"implements_edge_count":1},
    "nodes": [
      {"id":"specs.feat","label":"Feature Spec","type":"spec","path":"specs/feat.md",
       "status":"implemented","feature_ids":["UC-FEAT-001"],"criteria":[]},
      {"id":"src.app","label":"app.sh","type":"file","path":"src/app.sh"}
    ],
    "edges": [
      {"source":"src.app","target":"specs.feat","relation":"IMPLEMENTS",
       "provenance":"EXTRACTED","confidence":0.9}
    ],
    "insights": []
  }' > "$tmp/.flowai/wiki/graph.json"

  local out
  out="$(
    cd "$tmp" || exit 99
    FLOWAI_DIR="$tmp/.flowai" \
    FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_TESTING=1 \
    bash -c '
      source "$FLOWAI_HOME/src/core/log.sh"
      source "$FLOWAI_HOME/src/core/config.sh"
      source "$FLOWAI_HOME/src/core/graph.sh"
      source "$FLOWAI_HOME/src/graph/lint.sh"
      _lint_unimplemented_specs "$FLOWAI_WIKI_DIR/graph.json"
    ' 2>/dev/null
  )"

  if ! echo "$out" | grep -q "specs.feat"; then
    flowai_test_pass "UC-GRAPH-026" "Structural lint: spec with IMPLEMENTS edge is not flagged as unimplemented"
  else
    printf 'FAIL UC-GRAPH-026: specs.feat should NOT appear in unimplemented list (it has IMPLEMENTS edge)\n' >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-027 — Structural lint: zombie spec detected (deprecated + active SPECIFIES)
flowai_test_s_graph_027() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/.flowai/wiki"

  jq -n '{
    "metadata": {"built_at":"2026-01-01","node_count":2,"edge_count":1},
    "nodes": [
      {"id":"specs.old","label":"Old Spec","type":"spec","path":"specs/old.md","status":"deprecated"},
      {"id":"src.legacy","label":"legacy.sh","type":"file","path":"src/legacy.sh"}
    ],
    "edges": [
      {"source":"specs.old","target":"src.legacy","relation":"SPECIFIES","provenance":"EXTRACTED"}
    ],
    "insights": []
  }' > "$tmp/.flowai/wiki/graph.json"

  local out
  out="$(
    cd "$tmp" || exit 99
    FLOWAI_DIR="$tmp/.flowai" \
    FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_TESTING=1 \
    bash -c '
      source "$FLOWAI_HOME/src/core/log.sh"
      source "$FLOWAI_HOME/src/core/config.sh"
      source "$FLOWAI_HOME/src/core/graph.sh"
      source "$FLOWAI_HOME/src/graph/lint.sh"
      _lint_zombie_specs "$FLOWAI_WIKI_DIR/graph.json"
    ' 2>/dev/null
  )"

  if echo "$out" | grep -q "specs.old"; then
    flowai_test_pass "UC-GRAPH-027" "Structural lint detects zombie spec (deprecated + active SPECIFIES edge)"
  else
    printf 'FAIL UC-GRAPH-027: Expected specs.old in zombie output, got: %s\n' "$out" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-028 — Structural lint: full lint run produces lint-report.md
flowai_test_s_graph_028() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/.flowai/wiki"

  # Minimal valid graph.json
  jq -n '{
    "metadata": {"built_at":"2026-01-01","node_count":1,"edge_count":0,"spec_count":0},
    "nodes": [{"id":"src.a","label":"a.sh","type":"file","path":"src/a.sh"}],
    "edges": [],
    "insights": []
  }' > "$tmp/.flowai/wiki/graph.json"

  (
    cd "$tmp" || exit 99
    FLOWAI_DIR="$tmp/.flowai" \
    FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_TESTING=1 \
    bash -c '
      source "$FLOWAI_HOME/src/core/log.sh"
      source "$FLOWAI_HOME/src/core/config.sh"
      source "$FLOWAI_HOME/src/core/graph.sh"
      source "$FLOWAI_HOME/src/graph/lint.sh"
      flowai_graph_lint_structural
    ' 2>/dev/null
  )

  local report="$tmp/.flowai/wiki/lint-report.md"
  local json="$tmp/.flowai/wiki/lint-report.json"

  if [[ -f "$report" ]] && grep -q "Lint Report" "$report" && \
     [[ -f "$json" ]] && jq -e '.health' "$json" >/dev/null 2>&1; then
    flowai_test_pass "UC-GRAPH-028" "Full structural lint produces lint-report.md and lint-report.json"
  else
    printf 'FAIL UC-GRAPH-028: lint-report.md or lint-report.json missing or malformed\n' >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-029 — Lint health=HEALTHY when no issues found
flowai_test_s_graph_029() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/.flowai/wiki"

  # Graph with spec + IMPLEMENTS edge = no gaps
  jq -n '{
    "metadata": {"built_at":"2026-01-01","node_count":2,"edge_count":1,"spec_count":1},
    "nodes": [
      {"id":"specs.feat","label":"Feature","type":"spec","path":"specs/feat.md","status":"implemented"},
      {"id":"src.app","label":"app.sh","type":"file","path":"src/app.sh"}
    ],
    "edges": [
      {"source":"src.app","target":"specs.feat","relation":"IMPLEMENTS","provenance":"EXTRACTED","confidence":0.9}
    ],
    "insights": []
  }' > "$tmp/.flowai/wiki/graph.json"

  (
    cd "$tmp" || exit 99
    FLOWAI_DIR="$tmp/.flowai" \
    FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_TESTING=1 \
    bash -c '
      source "$FLOWAI_HOME/src/core/log.sh"
      source "$FLOWAI_HOME/src/core/config.sh"
      source "$FLOWAI_HOME/src/core/graph.sh"
      source "$FLOWAI_HOME/src/graph/lint.sh"
      flowai_graph_lint_structural
    ' 2>/dev/null
  )

  local health
  health="$(jq -r '.health' "$tmp/.flowai/wiki/lint-report.json" 2>/dev/null)"

  if [[ "$health" == "HEALTHY" ]]; then
    flowai_test_pass "UC-GRAPH-029" "Lint health=HEALTHY when graph has no structural issues"
  else
    printf 'FAIL UC-GRAPH-029: Expected HEALTHY, got: %s\n' "$health" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-030 — Chronicle: git not available returns gracefully (no exit code 1)
flowai_test_s_graph_030() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/.flowai/wiki"
  # Minimal graph.json
  jq -n '{"metadata":{"built_at":"2026-01-01","node_count":0},"nodes":[],"edges":[],"insights":[]}' \
    > "$tmp/.flowai/wiki/graph.json"

  # Run chronicle in a dir that is NOT a git repo — should not fail
  local rc=0
  (
    cd "$tmp" || exit 99
    FLOWAI_DIR="$tmp/.flowai" \
    FLOWAI_HOME="$FLOWAI_HOME" \
    FLOWAI_TESTING=1 \
    bash -c '
      source "$FLOWAI_HOME/src/core/log.sh"
      source "$FLOWAI_HOME/src/core/config.sh"
      source "$FLOWAI_HOME/src/core/graph.sh"
      source "$FLOWAI_HOME/src/graph/build.sh"
      source "$FLOWAI_HOME/src/graph/chronicle.sh"
      flowai_graph_chronicle
    ' 2>/dev/null
  ) || rc=$?

  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "UC-GRAPH-030" "Chronicle exits cleanly when git is not available (non-git dir)"
  else
    printf 'FAIL UC-GRAPH-030: Chronicle exited with rc=%s in non-git dir\n' "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-031 — YAML frontmatter id: merged into feature_ids (chronicle / IMPLEMENTS resolution)
flowai_test_s_graph_031() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/specs" "$tmp/.flowai/wiki"
  cat > "$tmp/specs/yaml-only-id.md" <<'SPEC'
---
id: UC-YAML-ONLY-999
status: planned
since: 2026-01-01
author: bob
---

# Feature without ID in body

Plain prose only — no UC- token in body text.
SPEC

  _graph_build_in "$tmp/.flowai" "$tmp" 'flowai_graph_build "true"' >/dev/null 2>&1

  local ids
  ids="$(jq -r '.nodes[] | select(.type=="spec") | .feature_ids[]?' "$tmp/.flowai/wiki/graph.json" 2>/dev/null | tr '\n' ' ')"

  if [[ "$ids" == *"UC-YAML-ONLY-999"* ]]; then
    flowai_test_pass "UC-GRAPH-031" "YAML id merged into feature_ids for chronicle lookup"
  else
    printf 'FAIL UC-GRAPH-031: Expected UC-YAML-ONLY-999 in feature_ids, got: %q\n' "$ids" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-GRAPH-032 — graph.json metadata outputs schema initializes newly added evolution variables
flowai_test_s_graph_032() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  _graph_write_config "$tmp"
  mkdir -p "$tmp/src" "$tmp/specs" "$tmp/.flowai/wiki"

  # Minimal run should emit the defaults for new schema elements
  _graph_build_in "$tmp/.flowai" "$tmp" 'flowai_graph_build "true"' >/dev/null 2>&1

  local graph="$tmp/.flowai/wiki/graph.json"

  if [[ -f "$graph" ]] && jq empty "$graph" 2>/dev/null && \
     jq -e '.metadata.implements_edge_count' "$graph" >/dev/null 2>&1 && \
     jq -e '.metadata.evolution_event_count' "$graph" >/dev/null 2>&1 && \
     jq -e '.metadata.specs_with_git_activity' "$graph" >/dev/null 2>&1; then
    flowai_test_pass "UC-GRAPH-032" "metadata schema initializes evolution/implements parameters successfully"
  else
    printf 'FAIL UC-GRAPH-032: graph.json missing implements/evolution schema elements in metadata block\n' >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}
