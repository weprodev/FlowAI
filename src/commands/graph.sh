#!/usr/bin/env bash
# FlowAI — graph command
# Manages the project knowledge graph and wiki.
#
# Usage: flowai graph <subcommand> [args...]
#
# Subcommands:
#   build [--force]     Build (or rebuild) the full knowledge graph
#   update              Incremental update — only processes changed files
#   chronicle           Mine git history for IMPLEMENTS edges + enrich spec frontmatter
#   lint [--structural] Coverage analysis: unimplemented specs, unspecified code, zombies
#   ingest <file>       Ingest a source document into the wiki
#   query "<question>"  Query the wiki; answer is filed back as a wiki page
#   status              Show graph health (nodes, edges, age, staleness)
#   report              Open GRAPH_REPORT.md in the terminal pager
#   rollback [--latest] Interactive version browser to restore a previous graph
#
# shellcheck shell=bash

set -euo pipefail

# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"
# shellcheck source=src/core/config.sh
source "$FLOWAI_HOME/src/core/config.sh"
# shellcheck source=src/core/graph.sh
source "$FLOWAI_HOME/src/core/graph.sh"
# shellcheck source=src/graph/build.sh
source "$FLOWAI_HOME/src/graph/build.sh"
# shellcheck source=src/graph/wiki.sh
source "$FLOWAI_HOME/src/graph/wiki.sh"
# shellcheck source=src/graph/lint.sh
source "$FLOWAI_HOME/src/graph/lint.sh"
# shellcheck source=src/graph/chronicle.sh
source "$FLOWAI_HOME/src/graph/chronicle.sh"

_graph_require_flowai_dir() {
  if [[ ! -f "${FLOWAI_DIR}/config.json" ]]; then
    log_error "Not a FlowAI project — run: flowai init"
    exit 1
  fi
}

_graph_require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required for graph commands. Install jq (e.g. brew install jq or apt-get install jq)."
    exit 1
  fi
}

# ─── Status ───────────────────────────────────────────────────────────────────

cmd_graph_status() {
  _graph_require_flowai_dir
  log_header "FlowAI Knowledge Graph — Status"
  flowai_graph_print_status

  if flowai_graph_exists; then
    printf '\n'
    log_info "Wiki directory: $(_graph_rel_path "$FLOWAI_WIKI_DIR")"
    log_info "Report:         $(_graph_rel_path "$FLOWAI_GRAPH_REPORT")"
    log_info "Graph JSON:     $(_graph_rel_path "$FLOWAI_GRAPH_JSON")"
    log_info "Index:          $(_graph_rel_path "$FLOWAI_GRAPH_INDEX")"
    log_info "Log:            $(_graph_rel_path "$FLOWAI_GRAPH_LOG")"
    printf '\n'
    log_info "Run 'flowai graph update' to refresh the graph."
    log_info "Run 'flowai graph report' to read the architectural summary."
  else
    printf '\n'
    log_info "Run 'flowai graph build' to create the initial knowledge graph."
  fi
}

# ─── Report ───────────────────────────────────────────────────────────────────

cmd_graph_report() {
  _graph_require_flowai_dir

  if [[ ! -f "$FLOWAI_GRAPH_REPORT" ]]; then
    log_error "No GRAPH_REPORT.md found. Run: flowai graph build"
    exit 1
  fi

  if command -v gum >/dev/null 2>&1; then
    gum pager < "$FLOWAI_GRAPH_REPORT"
  elif command -v less >/dev/null 2>&1; then
    less -R "$FLOWAI_GRAPH_REPORT" </dev/tty >/dev/tty 2>&1 || cat "$FLOWAI_GRAPH_REPORT"
  else
    cat "$FLOWAI_GRAPH_REPORT"
  fi
}

# ─── Build ────────────────────────────────────────────────────────────────────

cmd_graph_build() {
  _graph_require_flowai_dir
  local force="false"
  for arg in "$@"; do
    [[ "$arg" == "--force" || "$arg" == "-f" ]] && force="true"
  done

  if [[ "$force" == "true" ]]; then
    log_warn "Force rebuild: clearing structural + semantic caches..."
    rm -rf "$FLOWAI_GRAPH_CACHE_DIR/structural" 2>/dev/null || true
    rm -rf "$FLOWAI_GRAPH_CACHE_DIR/semantic" 2>/dev/null || true
    # Also clear SHA hash markers so the next incremental run re-validates all files.
    # These live at FLOWAI_GRAPH_CACHE_DIR/*.sha alongside the subdirectories.
    find "$FLOWAI_GRAPH_CACHE_DIR" -maxdepth 1 -name '*.sha' -delete 2>/dev/null || true
  fi

  flowai_graph_build "$force"
}

# ─── Update ───────────────────────────────────────────────────────────────────

cmd_graph_update() {
  _graph_require_flowai_dir
  flowai_graph_update
}

# ─── Ingest ───────────────────────────────────────────────────────────────────

cmd_graph_ingest() {
  _graph_require_flowai_dir
  local source="${1:-}"
  if [[ -z "$source" ]]; then
    log_error "Usage: flowai graph ingest <file>"
    exit 1
  fi
  flowai_wiki_ingest "$source"
}

# ─── Query ────────────────────────────────────────────────────────────────────

cmd_graph_query() {
  _graph_require_flowai_dir
  local question="${1:-}"

  if [[ -z "$question" ]]; then
    if command -v gum >/dev/null 2>&1; then
      question="$(gum input --placeholder "What do you want to know about this codebase?")"
    else
      read -r -p "Question: " question </dev/tty || true
    fi
  fi

  if [[ -z "$question" ]]; then
    log_error "No question provided."
    exit 1
  fi

  flowai_wiki_query "$question"
}

# ─── Chronicle ────────────────────────────────────────────────────────────────

cmd_graph_chronicle() {
  _graph_require_flowai_dir
  flowai_graph_chronicle
}

# ─── Rollback ────────────────────────────────────────────────────────────────

# List graph backups as an array, newest first.
_graph_list_backups() {
  local graph_dir graph_base
  graph_dir="$(dirname "$FLOWAI_GRAPH_JSON")"
  graph_base="$(basename "$FLOWAI_GRAPH_JSON")"
  find "$graph_dir" -maxdepth 1 -name "${graph_base}.*" \
    -not -name "*.pre-rollback" -not -name "*.lock" \
    2>/dev/null | sort -r
}

# Print a formatted version table.
_graph_print_version_table() {
  local -a backups=("$@")

  printf '\n'
  log_header "FlowAI Graph — Version History"
  printf '  %-4s %-22s %7s %7s %6s\n' "#" "Date" "Nodes" "Edges" "Size"
  printf '  %-4s %-22s %7s %7s %6s\n' "--" "--------------------" "-----" "-----" "----"

  if [[ -f "$FLOWAI_GRAPH_JSON" ]]; then
    local cur_nodes cur_edges cur_size
    cur_nodes="$(jq -r '.metadata.node_count // (.nodes | length) // "?"' "$FLOWAI_GRAPH_JSON" 2>/dev/null || echo '?')"
    cur_edges="$(jq -r '.metadata.edge_count // (.edges | length) // "?"' "$FLOWAI_GRAPH_JSON" 2>/dev/null || echo '?')"
    cur_size="$(du -h "$FLOWAI_GRAPH_JSON" 2>/dev/null | cut -f1 | tr -d ' ')"
    printf '  %-4s %-22s %7s %7s %6s  %s\n' "0" "(current)" "$cur_nodes" "$cur_edges" "$cur_size" "<- active"
  fi

  local i=1
  local graph_base
  graph_base="$(basename "$FLOWAI_GRAPH_JSON")"
  for backup in "${backups[@]}"; do
    local ts_raw ts_display nodes edges size
    ts_raw="$(basename "$backup" | sed "s/${graph_base}\.//")"
    ts_display="$(printf '%s' "$ts_raw" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)T\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/' 2>/dev/null || echo "$ts_raw")"
    nodes="$(jq -r '.metadata.node_count // (.nodes | length) // "?"' "$backup" 2>/dev/null || echo '?')"
    edges="$(jq -r '.metadata.edge_count // (.edges | length) // "?"' "$backup" 2>/dev/null || echo '?')"
    size="$(du -h "$backup" 2>/dev/null | cut -f1 | tr -d ' ')"
    printf '  %-4s %-22s %7s %7s %6s\n' "$i" "$ts_display" "$nodes" "$edges" "$size"
    i=$((i + 1))
  done
  printf '\n'
}

cmd_graph_rollback() {
  _graph_require_flowai_dir

  local -a backups=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && backups+=("$line")
  done < <(_graph_list_backups)

  if [[ ${#backups[@]} -eq 0 ]]; then
    log_error "No graph backups found. Nothing to roll back to."
    exit 1
  fi

  local selected_idx=1

  # --latest flag: non-interactive mode (scripts, CI, tests)
  local interactive=true
  for arg in "$@"; do
    [[ "$arg" == "--latest" ]] && interactive=false
  done
  [[ "${FLOWAI_TESTING:-0}" == "1" ]] && interactive=false

  if [[ "$interactive" == "true" ]]; then
    _graph_print_version_table "${backups[@]}"

    if command -v gum >/dev/null 2>&1; then
      local -a labels=()
      local i=1
      local graph_base
      graph_base="$(basename "$FLOWAI_GRAPH_JSON")"
      for backup in "${backups[@]}"; do
        local ts_raw ts_display
        ts_raw="$(basename "$backup" | sed "s/${graph_base}\.//")"
        ts_display="$(printf '%s' "$ts_raw" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)T\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/' 2>/dev/null || echo "$ts_raw")"
        labels+=("#${i}: ${ts_display}")
        i=$((i + 1))
      done
      local choice
      choice="$(gum choose "${labels[@]}")"
      selected_idx="$(printf '%s' "$choice" | sed 's/#\([0-9]*\):.*/\1/')"
    else
      printf '  Select version to restore (1-%d) [1]: ' "${#backups[@]}"
      local user_input
      read -r user_input < /dev/tty || true
      [[ -n "$user_input" ]] && selected_idx="$user_input"
    fi

    if ! [[ "$selected_idx" =~ ^[0-9]+$ ]] || [[ "$selected_idx" -lt 1 ]] || [[ "$selected_idx" -gt ${#backups[@]} ]]; then
      log_error "Invalid selection: $selected_idx (expected 1-${#backups[@]})"
      exit 1
    fi

    local newer_count=$((selected_idx - 1))
    local graph_base
    graph_base="$(basename "$FLOWAI_GRAPH_JSON")"
    local selected_ts
    selected_ts="$(basename "${backups[$((selected_idx - 1))]}" | sed "s/${graph_base}\.//")"

    printf '\n'
    printf '  %s!! WARNING: This will:%s\n' "${YELLOW}" "${RESET}"
    printf '     - Restore graph.json to version #%d (%s)\n' "$selected_idx" "$selected_ts"
    if [[ "$newer_count" -gt 0 ]]; then
      printf '     - %sDELETE %d newer version(s) permanently%s\n' "${RED}" "$newer_count" "${RESET}"
    fi
    printf '     - A pre-rollback safety copy will be saved\n\n'

    local confirmed=false
    if command -v gum >/dev/null 2>&1; then
      gum confirm "Are you sure?" && confirmed=true
    else
      printf '  Are you sure? [y/N]: '
      local ans
      read -r ans < /dev/tty || true
      [[ "$ans" =~ ^[yY] ]] && confirmed=true
    fi

    if [[ "$confirmed" != "true" ]]; then
      log_info "Rollback cancelled."
      exit 0
    fi
  fi

  # -- Execute rollback --
  local selected_backup="${backups[$((selected_idx - 1))]}"
  local graph_base
  graph_base="$(basename "$FLOWAI_GRAPH_JSON")"
  local selected_ts
  selected_ts="$(basename "$selected_backup" | sed "s/${graph_base}\.//")"

  if [[ -f "$FLOWAI_GRAPH_JSON" ]]; then
    cp "$FLOWAI_GRAPH_JSON" "${FLOWAI_GRAPH_JSON}.pre-rollback"
  fi

  cp "$selected_backup" "$FLOWAI_GRAPH_JSON"

  local deleted=0
  local i=0
  while [[ "$i" -lt $((selected_idx - 1)) ]]; do
    rm -f "${backups[$i]}"
    deleted=$((deleted + 1))
    i=$((i + 1))
  done

  _graph_generate_report 2>/dev/null || true
  _graph_generate_index 2>/dev/null || true

  flowai_graph_log_append "rollback" "restored from $selected_ts (deleted $deleted newer version(s))"
  log_success "Graph rolled back to $selected_ts"
  [[ "$deleted" -gt 0 ]] && log_info "$deleted newer version(s) removed."
  log_info "Pre-rollback state saved as graph.json.pre-rollback"
}


# ─── Lint ─────────────────────────────────────────────────────────────────────

# Lint has two modes:
#   --structural (default): fast pure-bash coverage analysis — no LLM
#   --semantic:             LLM-based wiki health check (orphans, contradictions)
cmd_graph_lint() {
  _graph_require_flowai_dir
  local mode="structural"
  for arg in "$@"; do
    [[ "$arg" == "--semantic" ]] && mode="semantic"
    [[ "$arg" == "--structural" ]] && mode="structural"
  done

  if [[ "$mode" == "semantic" ]]; then
    log_info "Running semantic lint (LLM-based wiki health check)..."
    flowai_wiki_lint
  else
    log_info "Running structural lint (coverage analysis, no LLM)..."
    flowai_graph_lint_structural
    printf '\n'
    log_info "Read full report: $(_graph_rel_path "$FLOWAI_WIKI_DIR")/lint-report.md"
    log_info "Machine-readable: $(_graph_rel_path "$FLOWAI_WIKI_DIR")/lint-report.json"
    log_info "For wiki health check: flowai graph lint --semantic"
  fi
}

# ─── Usage ────────────────────────────────────────────────────────────────────

graph_usage() {
  cat <<EOF
${BOLD}flowai graph — knowledge graph management${RESET}

Usage:
  flowai graph ${CYAN}build${RESET} [--force]        Build (or rebuild) the knowledge graph
  flowai graph ${CYAN}update${RESET}                 Incremental update (changed files only)
  flowai graph ${CYAN}chronicle${RESET}              Mine git history → IMPLEMENTS edges + spec evolution
  flowai graph ${CYAN}lint${RESET} [--structural]     Coverage analysis (default: structural, no LLM)
  flowai graph ${CYAN}lint${RESET} --semantic         Wiki health check: orphans, contradictions (LLM)
  flowai graph ${CYAN}ingest${RESET} <file>           Ingest a document into the wiki
  flowai graph ${CYAN}query${RESET} "<question>"      Query the wiki + file answer back
  flowai graph ${CYAN}status${RESET}                  Show graph health and file locations
  flowai graph ${CYAN}rollback${RESET}                 Restore graph.json to the previous version
  flowai graph ${CYAN}report${RESET}                  Read GRAPH_REPORT.md in terminal pager

The compiled graph lives under graph.wiki_dir (default: .flowai/wiki/)
  GRAPH_REPORT.md  ← usually docs/GRAPH_REPORT.md — god nodes, spec status dashboard, SDD coverage
  index.md         ← full catalog with project timeline
  graph.json       ← full graph with provenance-tagged edges
  lint-report.md   ← coverage gaps, zombie specs, decision debt
  log.md           ← chronological operation log

Spec-Driven Development workflow:
  ${CYAN}1.${RESET} Write spec in specs/ with frontmatter (status, since, author, id)
  ${CYAN}2.${RESET} flowai graph build          ← spec becomes a graph node
  ${CYAN}3.${RESET} Implement the feature       ← commit message: "Implements UC-AUTH-001"
  ${CYAN}4.${RESET} flowai graph chronicle      ← IMPLEMENTS edges created, evolution recorded
  ${CYAN}5.${RESET} flowai graph lint           ← verify no gaps remain

Edge types:
  ${GREEN}SPECIFIES${RESET}    — spec → code (intent → implementation)
  ${GREEN}IMPLEMENTS${RESET}   — code → spec (commit evidence of implementation)
  ${YELLOW}INFERRED${RESET}     — reasonable inference (treat as hypothesis)
  ${RED}AMBIGUOUS${RESET}    — flagged for review

Examples:
  flowai graph build
  flowai graph chronicle
  flowai graph lint
  flowai graph lint --semantic
  flowai graph ingest docs/ARCHITECTURE.md
  flowai graph query "Which specs have no implementation coverage?"
  flowai graph report
EOF
}

# ─── Entry Point ──────────────────────────────────────────────────────────────

subcmd="${1:-}"
shift || true

# Help should work without jq; all other graph operations depend on it.
if [[ "$subcmd" != "-h" && "$subcmd" != "--help" && "$subcmd" != "help" ]]; then
  _graph_require_jq
fi

case "$subcmd" in
  build)          cmd_graph_build "$@" ;;
  update)         cmd_graph_update ;;
  chronicle)      cmd_graph_chronicle ;;
  ingest)         cmd_graph_ingest "$@" ;;
  query)          cmd_graph_query "$@" ;;
  lint)           cmd_graph_lint "$@" ;;
  status|"")      cmd_graph_status ;;
  report)         cmd_graph_report ;;
  rollback)       cmd_graph_rollback "$@" ;;
  -h|--help|help) graph_usage ;;
  *)
    log_error "Unknown graph subcommand: $subcmd"
    graph_usage
    exit 1
    ;;
esac
