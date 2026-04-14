#!/usr/bin/env bash
# FlowAI Knowledge Graph — edge-case test suite
#
# Tests cover:
#   GREDGE-001  flowai_graph_is_stale returns 0 (stale) when graph.json does not exist
#   GREDGE-002  flowai_graph_is_stale returns 1 (fresh) for a recently created graph.json
#   GREDGE-003  flowai_graph_exists returns 1 when only graph.json exists (no report)
#   GREDGE-004  flowai_graph_exists returns 1 when only report exists (no graph.json)
#   GREDGE-005  flowai_graph_context_block returns empty when graph doesn't exist
#   GREDGE-006  flowai_graph_log_append creates wiki directory if missing
#   GREDGE-007  flowai_graph_resolve_paths respects FLOWAI_GRAPH_WIKI_DIR env override
#   GREDGE-008  flowai_graph_is_enabled returns 1 (disabled) when config has graph.enabled=false
#
# Expects tests/lib/harness.sh sourced first (see tests/run.sh).
# shellcheck shell=bash

source "$FLOWAI_HOME/src/core/log.sh"

# ─── Tests ────────────────────────────────────────────────────────────────────

# GREDGE-001 — flowai_graph_is_stale returns 0 (stale) when graph.json does not exist
flowai_test_s_gredge_001() {
  local scratch
  scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' RETURN

  mkdir -p "$scratch/.flowai"
  printf '{}' > "$scratch/.flowai/config.json"

  local rc=0
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -c '
    cd "'"$scratch"'" || exit 99
    source "$FLOWAI_HOME/src/core/log.sh"
    source "$FLOWAI_HOME/src/core/config.sh"
    source "$FLOWAI_HOME/src/core/graph.sh"
    flowai_graph_is_stale
  ' 2>/dev/null || rc=$?

  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "GREDGE-001" "flowai_graph_is_stale returns 0 (stale) when graph.json does not exist"
  else
    printf 'FAIL GREDGE-001: Expected rc=0 (stale), got rc=%s\n' "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# GREDGE-002 — flowai_graph_is_stale returns 1 (fresh) for a recently created graph.json
flowai_test_s_gredge_002() {
  local scratch
  scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' RETURN

  mkdir -p "$scratch/.flowai"
  printf '{}' > "$scratch/.flowai/config.json"

  # Create both graph.json and GRAPH_REPORT.md (flowai_graph_exists needs both)
  mkdir -p "$scratch/.flowai/wiki"
  printf '{"metadata":{"node_count":1},"nodes":[],"edges":[]}' > "$scratch/.flowai/wiki/graph.json"
  echo "# Report" > "$scratch/GRAPH_REPORT.md"

  local rc=0
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -c '
    cd "'"$scratch"'" || exit 99
    source "$FLOWAI_HOME/src/core/log.sh"
    source "$FLOWAI_HOME/src/core/config.sh"
    source "$FLOWAI_HOME/src/core/graph.sh"
    flowai_graph_is_stale
  ' 2>/dev/null || rc=$?

  if [[ "$rc" -eq 1 ]]; then
    flowai_test_pass "GREDGE-002" "flowai_graph_is_stale returns 1 (fresh) for a recently created graph.json"
  else
    printf 'FAIL GREDGE-002: Expected rc=1 (fresh), got rc=%s\n' "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# GREDGE-003 — flowai_graph_exists returns 1 when only graph.json exists (no report)
flowai_test_s_gredge_003() {
  local scratch
  scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' RETURN

  mkdir -p "$scratch/.flowai"
  printf '{}' > "$scratch/.flowai/config.json"

  # Create graph.json but NOT GRAPH_REPORT.md
  mkdir -p "$scratch/.flowai/wiki"
  printf '{"metadata":{"node_count":1},"nodes":[],"edges":[]}' > "$scratch/.flowai/wiki/graph.json"

  local rc=0
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -c '
    cd "'"$scratch"'" || exit 99
    source "$FLOWAI_HOME/src/core/log.sh"
    source "$FLOWAI_HOME/src/core/config.sh"
    source "$FLOWAI_HOME/src/core/graph.sh"
    flowai_graph_exists
  ' 2>/dev/null || rc=$?

  if [[ "$rc" -eq 1 ]]; then
    flowai_test_pass "GREDGE-003" "flowai_graph_exists returns 1 when only graph.json exists (no report)"
  else
    printf 'FAIL GREDGE-003: Expected rc=1, got rc=%s\n' "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# GREDGE-004 — flowai_graph_exists returns 1 when only report exists (no graph.json)
flowai_test_s_gredge_004() {
  local scratch
  scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' RETURN

  mkdir -p "$scratch/.flowai"
  printf '{}' > "$scratch/.flowai/config.json"

  # Create GRAPH_REPORT.md but NOT graph.json
  echo "# Report" > "$scratch/GRAPH_REPORT.md"

  local rc=0
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -c '
    cd "'"$scratch"'" || exit 99
    source "$FLOWAI_HOME/src/core/log.sh"
    source "$FLOWAI_HOME/src/core/config.sh"
    source "$FLOWAI_HOME/src/core/graph.sh"
    flowai_graph_exists
  ' 2>/dev/null || rc=$?

  if [[ "$rc" -eq 1 ]]; then
    flowai_test_pass "GREDGE-004" "flowai_graph_exists returns 1 when only report exists (no graph.json)"
  else
    printf 'FAIL GREDGE-004: Expected rc=1, got rc=%s\n' "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# GREDGE-005 — flowai_graph_context_block returns empty when graph doesn't exist
flowai_test_s_gredge_005() {
  local scratch
  scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' RETURN

  mkdir -p "$scratch/.flowai"
  printf '{}' > "$scratch/.flowai/config.json"

  local block
  block="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -c '
    cd "'"$scratch"'" || exit 99
    source "$FLOWAI_HOME/src/core/log.sh"
    source "$FLOWAI_HOME/src/core/config.sh"
    source "$FLOWAI_HOME/src/core/graph.sh"
    flowai_graph_context_block
  ' 2>/dev/null)"

  if [[ -z "$block" ]]; then
    flowai_test_pass "GREDGE-005" "flowai_graph_context_block returns empty when graph doesn't exist"
  else
    printf 'FAIL GREDGE-005: Expected empty output, got: %s\n' "$block" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# GREDGE-006 — flowai_graph_log_append creates wiki directory if missing
flowai_test_s_gredge_006() {
  local scratch
  scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' RETURN

  mkdir -p "$scratch/.flowai"
  printf '{}' > "$scratch/.flowai/config.json"

  # Deliberately do NOT create the wiki directory beforehand.
  # Note: flowai_graph_resolve_paths (called at source time) does mkdir -p,
  # so we set FLOWAI_GRAPH_WIKI_DIR to a custom path that does not exist yet
  # and verify log_append still works via its own mkdir -p.
  local custom_wiki="$scratch/.flowai/custom_wiki"

  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" \
      FLOWAI_GRAPH_WIKI_DIR="$custom_wiki" bash -c '
    cd "'"$scratch"'" || exit 99
    source "$FLOWAI_HOME/src/core/log.sh"
    source "$FLOWAI_HOME/src/core/config.sh"
    source "$FLOWAI_HOME/src/core/graph.sh"
    flowai_graph_log_append "test-op" "edge-case test"
  ' 2>/dev/null

  local log_file="$custom_wiki/log.md"
  if [[ -d "$custom_wiki" ]] && [[ -f "$log_file" ]] && grep -q "test-op" "$log_file"; then
    flowai_test_pass "GREDGE-006" "flowai_graph_log_append creates wiki directory if missing"
  else
    printf 'FAIL GREDGE-006: Expected wiki dir and log.md to exist with test-op entry\n' >&2
    printf '  dir exists: %s, log exists: %s\n' \
      "$([[ -d "$custom_wiki" ]] && echo yes || echo no)" \
      "$([[ -f "$log_file" ]] && echo yes || echo no)" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# GREDGE-007 — flowai_graph_resolve_paths respects FLOWAI_GRAPH_WIKI_DIR env override
flowai_test_s_gredge_007() {
  local scratch
  scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' RETURN

  mkdir -p "$scratch/.flowai"
  printf '{}' > "$scratch/.flowai/config.json"

  local custom_dir="$scratch/my_custom_wiki"

  local resolved_wiki
  resolved_wiki="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" \
      FLOWAI_GRAPH_WIKI_DIR="$custom_dir" bash -c '
    cd "'"$scratch"'" || exit 99
    source "$FLOWAI_HOME/src/core/log.sh"
    source "$FLOWAI_HOME/src/core/config.sh"
    source "$FLOWAI_HOME/src/core/graph.sh"
    printf "%s" "$FLOWAI_WIKI_DIR"
  ' 2>/dev/null)"

  if [[ "$resolved_wiki" == "$custom_dir" ]]; then
    flowai_test_pass "GREDGE-007" "flowai_graph_resolve_paths respects FLOWAI_GRAPH_WIKI_DIR env override"
  else
    printf 'FAIL GREDGE-007: Expected FLOWAI_WIKI_DIR=%s, got: %s\n' "$custom_dir" "$resolved_wiki" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# GREDGE-008 — flowai_graph_is_enabled returns 1 (disabled) when config has graph.enabled=false
flowai_test_s_gredge_008() {
  local scratch
  scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' RETURN

  mkdir -p "$scratch/.flowai"
  printf '{"graph":{"enabled":false}}' > "$scratch/.flowai/config.json"

  local rc=0
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -c '
    cd "'"$scratch"'" || exit 99
    source "$FLOWAI_HOME/src/core/log.sh"
    source "$FLOWAI_HOME/src/core/config.sh"
    source "$FLOWAI_HOME/src/core/graph.sh"
    flowai_graph_is_enabled
  ' 2>/dev/null || rc=$?

  if [[ "$rc" -eq 1 ]]; then
    flowai_test_pass "GREDGE-008" "flowai_graph_is_enabled returns 1 (disabled) when config has graph.enabled=false"
  else
    printf 'FAIL GREDGE-008: Expected rc=1 (disabled), got rc=%s\n' "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}
