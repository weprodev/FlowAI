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

# ─── Status ───────────────────────────────────────────────────────────────────

cmd_graph_status() {
  _graph_require_flowai_dir
  log_header "FlowAI Knowledge Graph — Status"
  flowai_graph_print_status

  if flowai_graph_exists; then
    printf '\n'
    log_info "Wiki directory: ${FLOWAI_WIKI_DIR#$PWD/}"
    log_info "Report:         ${FLOWAI_GRAPH_REPORT#$PWD/}"
    log_info "Graph JSON:     ${FLOWAI_GRAPH_JSON#$PWD/}"
    log_info "Index:          ${FLOWAI_GRAPH_INDEX#$PWD/}"
    log_info "Log:            ${FLOWAI_GRAPH_LOG#$PWD/}"
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
    log_info "Read full report: ${FLOWAI_WIKI_DIR#$PWD/}/lint-report.md"
    log_info "Machine-readable: ${FLOWAI_WIKI_DIR#$PWD/}/lint-report.json"
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
  flowai graph ${CYAN}report${RESET}                  Read GRAPH_REPORT.md in terminal pager

The knowledge graph lives at: .flowai/wiki/
  GRAPH_REPORT.md  ← start here: god nodes, spec status dashboard, SDD coverage
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

case "$subcmd" in
  build)          cmd_graph_build "$@" ;;
  update)         cmd_graph_update ;;
  chronicle)      cmd_graph_chronicle ;;
  ingest)         cmd_graph_ingest "$@" ;;
  query)          cmd_graph_query "$@" ;;
  lint)           cmd_graph_lint "$@" ;;
  status|"")      cmd_graph_status ;;
  report)         cmd_graph_report ;;
  -h|--help|help) graph_usage ;;
  *)
    log_error "Unknown graph subcommand: $subcmd"
    graph_usage
    exit 1
    ;;
esac
