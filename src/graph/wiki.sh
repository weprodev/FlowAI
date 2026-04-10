#!/usr/bin/env bash
# FlowAI — Knowledge Graph wiki operations
#
# Implements Karpathy's three wiki operations, adapted for FlowAI:
#
#   ingest  — Read a new source document, extract knowledge, update wiki pages,
#             update index.md, append to log.md
#   query   — Answer a question using the wiki, file the answer back as a new
#             wiki page so the knowledge compounds
#   lint    — Health-check the wiki: orphans, contradictions, stale claims
#
# All operations use flowai_ai_run() — they inherit the project's configured AI
# tool and model. No new AI plumbing needed.
#
# shellcheck shell=bash

# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"
# shellcheck source=src/core/config.sh
source "$FLOWAI_HOME/src/core/config.sh"
# shellcheck source=src/core/graph.sh
source "$FLOWAI_HOME/src/core/graph.sh"
# shellcheck source=src/core/ai.sh
source "$FLOWAI_HOME/src/core/ai.sh"

# ─── Ingest ───────────────────────────────────────────────────────────────────

# Ingest a single source document into the knowledge wiki.
# The LLM reads the source, extracts key knowledge, and updates relevant wiki
# pages (creating new ones as needed), then updates index.md and log.md.
#
# Usage: flowai_wiki_ingest <file_or_url>
flowai_wiki_ingest() {
  local source="${1:-}"
  if [[ -z "$source" ]]; then
    log_error "Usage: flowai graph ingest <file>"
    return 1
  fi

  if [[ ! -f "$source" ]]; then
    log_error "Source file not found: $source"
    return 1
  fi

  local rel_path="${source#$PWD/}"
  log_header "Knowledge Graph — Ingest: $rel_path"

  mkdir -p "$FLOWAI_WIKI_DIR"

  # Build the ingest prompt
  local prompt_file
  prompt_file="$(mktemp /tmp/flowai_ingest.XXXXXX.md)"

  cat > "$prompt_file" <<INGEST_PROMPT
# Knowledge Wiki — Ingest Operation

You are maintaining the FlowAI project knowledge wiki at: .flowai/wiki/

## Task

Read the source document below and integrate its knowledge into the wiki:

1. **Extract key knowledge**: concepts, decisions, patterns, dependencies,
   architectural rationale, and any "why" reasoning.

2. **Update or create wiki pages**: Each important concept should either update
   an existing wiki page (if one covers that topic) or create a new one.
   Wiki pages live at: .flowai/wiki/<concept-name>.md

3. **Update the index**: Append or update the entry for each touched page in
   .flowai/wiki/index.md (format: "- **[title](path)** — one-line summary")

4. **Note contradictions**: If the source contradicts something already in the
   wiki, flag it clearly with a "⚡ Contradiction:" note.

5. **Announce completion**: List the wiki pages you created or updated.

## Source: ${rel_path}

$(cat "$source")
INGEST_PROMPT

  flowai_ai_run "master" "$prompt_file" "true"
  rm -f "$prompt_file"

  # Append to operation log
  flowai_graph_log_append "ingest" "$rel_path"

  log_success "Ingest complete. Run 'flowai graph update' to refresh the structural graph."
}

# ─── Query ────────────────────────────────────────────────────────────────────

# Query the knowledge wiki and file the answer back as a new wiki page.
# Good answers compound in the knowledge base — they shouldn't disappear into
# chat history.
#
# Usage: flowai_wiki_query "<question>"
flowai_wiki_query() {
  local question="${1:-}"
  if [[ -z "$question" ]]; then
    log_error "Usage: flowai graph query \"<question>\""
    return 1
  fi

  log_header "Knowledge Graph — Query"
  log_info "Question: $question"

  mkdir -p "$FLOWAI_WIKI_DIR"

  # Build the query prompt
  local prompt_file
  prompt_file="$(mktemp /tmp/flowai_query.XXXXXX.md)"

  # Generate a filesystem-safe slug for the answer page
  local slug
  slug="$(printf '%s' "$question" | tr '[:upper:]' '[:lower:]' | \
          sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//' | \
          cut -c1-60)"
  local answer_page="${FLOWAI_WIKI_DIR}/query-${slug}.md"

  cat > "$prompt_file" <<QUERY_PROMPT
# Knowledge Wiki — Query Operation

You are answering a question about this project using the compiled knowledge base.

## Navigation Protocol

First, read these files in order:
1. .flowai/wiki/GRAPH_REPORT.md — for architectural orientation
2. .flowai/wiki/index.md — to find relevant wiki pages
3. The specific wiki pages relevant to the question

Then synthesize a comprehensive answer.

## Question

${question}

## Output

After answering the question in our conversation, save your answer as a wiki
page at: ${answer_page#$PWD/}

The page should follow this format:
\`\`\`markdown
# [Question as Title]

> Query filed: $(date +%Y-%m-%d)

## Answer

[Comprehensive answer with citations to specific wiki pages and source files]

## Sources

- [list of wiki pages and source files consulted]
\`\`\`

Important: Filing the answer compounds the knowledge base. Future questions on
the same topic will find this page and won't require re-derivation.
QUERY_PROMPT

  flowai_ai_run "master" "$prompt_file" "true"
  rm -f "$prompt_file"

  # Append to operation log
  flowai_graph_log_append "query" "$question"

  log_success "Query complete."
  if [[ -f "$answer_page" ]]; then
    log_info "Answer filed: ${answer_page#$PWD/}"
  fi
}

# ─── Lint ─────────────────────────────────────────────────────────────────────

# Health-check the knowledge wiki.
# Detects: orphan pages, contradictions, stale claims, missing cross-references,
# god nodes that have no wiki page, concepts mentioned but undocumented.
#
# Usage: flowai_wiki_lint
flowai_wiki_lint() {
  log_header "Knowledge Graph — Lint"

  if ! flowai_graph_exists; then
    log_error "No knowledge graph found. Run: flowai graph build"
    return 1
  fi

  mkdir -p "$FLOWAI_WIKI_DIR"

  local prompt_file
  prompt_file="$(mktemp /tmp/flowai_lint.XXXXXX.md)"

  cat > "$prompt_file" <<LINT_PROMPT
# Knowledge Wiki — Lint Operation

You are performing a health check on the FlowAI project knowledge wiki.

## Wiki Location

All wiki pages are in: .flowai/wiki/

## Lint Checklist

Systematically check each of the following and report findings:

### 1. Orphan Pages
List all wiki pages in .flowai/wiki/ that have no inbound links from other wiki pages.
These are isolated knowledge islands that may indicate poor cross-referencing.

### 2. Contradictions
Identify any cases where two wiki pages make conflicting claims about the same subject.
Flag with: "⚡ Contradiction: page-a.md vs page-b.md — [nature of conflict]"

### 3. Stale Claims
Identify claims in wiki pages that reference files or APIs that no longer exist
in the codebase. Cross-reference against: .flowai/wiki/graph.json (nodes.path fields).

### 4. Missing God Node Pages
Check .flowai/wiki/GRAPH_REPORT.md for god nodes. For each god node, verify a wiki
page exists covering it. List any god nodes missing wiki coverage.

### 5. Undocumented Concepts
Identify important concepts that appear repeatedly in wiki pages but lack their own
dedicated page. Suggest page titles for each.

### 6. Missing Cross-References
Find cases where wiki page A and wiki page B clearly cover related topics but
don't link to each other.

## Output Format

Produce a lint report with sections matching the checklist above.
For each issue found, suggest a concrete fix.
Conclude with a health score: HEALTHY / NEEDS-ATTENTION / CRITICAL.

End by appending the lint summary to .flowai/wiki/log.md:
## [$(date +%Y-%m-%d)] lint | <health-score>
LINT_PROMPT

  flowai_ai_run "master" "$prompt_file" "true"
  rm -f "$prompt_file"

  flowai_graph_log_append "lint" "completed"
  log_success "Lint complete."
}
