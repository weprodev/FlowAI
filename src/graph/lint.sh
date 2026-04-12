#!/usr/bin/env bash
# FlowAI — Knowledge Graph structural lint engine
#
# Pure-bash graph analysis — no LLM required. Answers provable structural
# questions about the gap between specs, implementation, and history:
#
#   Coverage analysis:
#     - Specs with no IMPLEMENTS back-edge     → unimplemented
#     - Files with no SPECIFIES in-edge        → unspecified code
#     - Specs with status=deprecated + active code  → zombie specs
#
#   Decision debt:
#     - ADRs in "proposed" state for >30 days  → decision debt
#
#   Lifecycle consistency:
#     - Specs with status mismatch (claims implemented but no git evidence)
#     - Spec criteria with no corresponding test files
#
# Output: machine-readable JSON to .flowai/wiki/lint-report.json
#         human-readable markdown to .flowai/wiki/lint-report.md
#         appends summary to .flowai/wiki/log.md
#
# shellcheck shell=bash

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Days since an ISO-8601 date string (YYYY-MM-DD or YYYY-MM-DDTHH:MM:SSZ).
_lint_days_since() {
  local date_str="$1"
  # Normalize to YYYY-MM-DD
  local ymd="${date_str:0:10}"
  local then_epoch now_epoch
  if date -j -f "%Y-%m-%d" "$ymd" +%s >/dev/null 2>&1; then
    # macOS
    then_epoch="$(date -j -f "%Y-%m-%d" "$ymd" +%s 2>/dev/null || echo 0)"
  else
    # GNU
    then_epoch="$(date -d "$ymd" +%s 2>/dev/null || echo 0)"
  fi
  now_epoch="$(date +%s)"
  echo $(( (now_epoch - then_epoch) / 86400 ))
}

# ─── Coverage Analysis ────────────────────────────────────────────────────────

# Finds spec nodes with no IMPLEMENTS (code→spec) back-edge.
# Returns JSONL of {id, label, path, status, feature_ids}
_lint_unimplemented_specs() {
  local graph_file="$1"
  [[ -f "$graph_file" ]] || return 0

  # Collect the set of spec node IDs that are targets of an IMPLEMENTS edge
  jq -r '
    (.edges | map(select(.relation == "IMPLEMENTS")) | map(.target) | unique) as $implemented |
    .nodes |
    map(select(.type == "spec")) |
    map(select(.id as $id | ($implemented | index($id)) == null)) |
    map(select(.status != "deprecated")) |
    .[] |
    "\(.id)\t\(.label)\t\(.path // .id)\t\(.status // "unknown")\t\((.feature_ids // []) | join(","))"
  ' "$graph_file" 2>/dev/null || true
}

# Finds file nodes (type=file) with no SPECIFIES in-edge (no spec covers them).
# Returns JSONL of {id, label, path}
_lint_unspecified_files() {
  local graph_file="$1"
  [[ -f "$graph_file" ]] || return 0

  jq -r '
    (.edges | map(select(.relation == "SPECIFIES")) | map(.target) | unique) as $specified |
    .nodes |
    map(select(.type == "file")) |
    map(select(.id as $id | ($specified | index($id)) == null)) |
    map(select(.path // "" | test("src/"))) |
    .[] |
    "\(.id)\t\(.label)\t\(.path // .id)"
  ' "$graph_file" 2>/dev/null || true
}

# Finds spec nodes with status=deprecated that still have active SPECIFIES edges.
# Returns JSONL of {spec_id, spec_label, code_id}
_lint_zombie_specs() {
  local graph_file="$1"
  [[ -f "$graph_file" ]] || return 0

  jq -r '
    (.nodes | map(select(.type == "spec" and .status == "deprecated")) | map(.id)) as $deprecated |
    .edges |
    map(select(.relation == "SPECIFIES")) |
    map(select(.source as $s | ($deprecated | index($s)) != null)) |
    .[] |
    "\(.source)\t\(.target)"
  ' "$graph_file" 2>/dev/null || true
}

# Finds ADR nodes in "proposed" status for more than $max_days days.
# Returns JSONL of {id, label, path, since, days_old}
_lint_decision_debt() {
  local graph_file="$1"
  local max_days="${2:-30}"
  [[ -f "$graph_file" ]] || return 0

  local now_epoch
  now_epoch="$(date +%s)"

  jq -r \
    --arg max "$max_days" \
    --arg now "$now_epoch" '
    .nodes |
    map(select(.type == "spec" and (.subtype == "adr") and (.adr_status == "proposed" or .adr_status == "draft"))) |
    map(select(.since != null)) |
    .[] |
    "\(.id)\t\(.label)\t\(.path // .id)\t\(.since)"
  ' "$graph_file" 2>/dev/null | while IFS=$'\t' read -r id label path since; do
      local days
      days="$(_lint_days_since "$since")"
      if [[ "$days" -gt "$max_days" ]]; then
        printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$label" "$path" "$since" "$days"
      fi
  done
}

# Finds spec nodes where status claims "implemented" but evolution array is empty
# (no git evidence of implementation). These are self-declared without proof.
_lint_unverified_implemented_claims() {
  local graph_file="$1"
  [[ -f "$graph_file" ]] || return 0

  jq -r '
    .nodes |
    map(select(
      .type == "spec" and
      .status == "implemented" and
      ((.evolution // []) | length) == 0
    )) |
    .[] |
    "\(.id)\t\(.label)\t\(.path // .id)"
  ' "$graph_file" 2>/dev/null || true
}

# ─── Lint Runner ──────────────────────────────────────────────────────────────

# Run full structural lint and write reports.
flowai_graph_lint_structural() {
  local graph_file="${FLOWAI_GRAPH_JSON}"
  local report_file="${FLOWAI_WIKI_DIR}/lint-report.md"
  local json_file="${FLOWAI_WIKI_DIR}/lint-report.json"

  if [[ ! -f "$graph_file" ]]; then
    log_error "No graph.json found. Run: flowai graph build"
    return 1
  fi

  log_header "FlowAI Knowledge Graph — Structural Lint"

  local -i unimplemented_count=0
  local -i unspecified_count=0
  local -i zombie_count=0
  local -i debt_count=0
  local -i unverified_count=0

  # ── Collect findings ──────────────────────────────────────────────────────

  # Use temporary files sequentially to keep memory usage low and pipeline robust
  local tmp_unimpl tmp_unspec tmp_zombie tmp_debt tmp_unverified
  tmp_unimpl="$(mktemp "${TMPDIR:-/tmp}/flowai_lint_unimpl_XXXXXX")"
  tmp_unspec="$(mktemp "${TMPDIR:-/tmp}/flowai_lint_unspec_XXXXXX")"
  tmp_zombie="$(mktemp "${TMPDIR:-/tmp}/flowai_lint_zomb_XXXXXX")"
  tmp_debt="$(mktemp "${TMPDIR:-/tmp}/flowai_lint_debt_XXXXXX")"
  tmp_unverified="$(mktemp "${TMPDIR:-/tmp}/flowai_lint_unv_XXXXXX")"
  trap 'rm -f "${tmp_unimpl:-}" "${tmp_unspec:-}" "${tmp_zombie:-}" "${tmp_debt:-}" "${tmp_unverified:-}" 2>/dev/null' RETURN

  _lint_unimplemented_specs "$graph_file" > "$tmp_unimpl"
  _lint_unspecified_files   "$graph_file" > "$tmp_unspec"
  _lint_zombie_specs        "$graph_file" > "$tmp_zombie"
  _lint_decision_debt       "$graph_file" > "$tmp_debt"
  _lint_unverified_implemented_claims "$graph_file" > "$tmp_unverified"

  # grep -c exits 1 when count is 0 — use `|| true` so we do not append a second "0"
  unimplemented_count=$(grep -c . "$tmp_unimpl" 2>/dev/null || true)
  unspecified_count=$(grep -c . "$tmp_unspec" 2>/dev/null || true)
  zombie_count=$(grep -c . "$tmp_zombie" 2>/dev/null || true)
  debt_count=$(grep -c . "$tmp_debt" 2>/dev/null || true)
  unverified_count=$(grep -c . "$tmp_unverified" 2>/dev/null || true)

  local total_issues=$(( unimplemented_count + zombie_count + debt_count ))
  local health
  if   [[ "$total_issues" -eq 0 ]]; then health="HEALTHY"
  elif [[ "$total_issues" -le 3 ]]; then health="NEEDS-ATTENTION"
  else                                    health="CRITICAL"
  fi

  log_info "Specs without implementation:  ${unimplemented_count}"
  log_info "Files without spec coverage:   ${unspecified_count}"
  log_info "Zombie specs (deprecated+code): ${zombie_count}"
  log_info "Decision debt (stale ADRs):    ${debt_count}"
  log_info "Unverified 'implemented' claims: ${unverified_count}"

  # ── Write markdown report ─────────────────────────────────────────────────

  local built_at
  built_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  mkdir -p "$FLOWAI_WIKI_DIR"

  {
    cat <<REPORT_HEADER
# FlowAI Knowledge Graph — Lint Report

> Run: ${built_at}
> Health: **${health}**

---

## Summary

| Check | Count | Severity |
|---|---|---|
| Specs without implementation | ${unimplemented_count} | $([ "$unimplemented_count" -gt 0 ] && echo "⚠ Warning" || echo "✓ OK") |
| Files without spec coverage | ${unspecified_count} | $([ "$unspecified_count" -gt 5 ] && echo "⚠ Warning" || echo "ℹ Info") |
| Zombie specs (deprecated but still referenced) | ${zombie_count} | $([ "$zombie_count" -gt 0 ] && echo "🔴 Error" || echo "✓ OK") |
| Decision debt (ADRs proposed >30d) | ${debt_count} | $([ "$debt_count" -gt 0 ] && echo "⚠ Warning" || echo "✓ OK") |
| Unverified 'implemented' claims | ${unverified_count} | $([ "$unverified_count" -gt 0 ] && echo "ℹ Info" || echo "✓ OK") |

---

## Unimplemented Specs

Spec documents that declare features but have no \`IMPLEMENTS\` back-edge
from source code. These are either planned features or implementation gaps.

> Action: Add \`status: planned\` to frontmatter if intentional, or implement the feature.

REPORT_HEADER

    if [[ -s "$tmp_unimpl" ]]; then
      while IFS=$'\t' read -r id label path status fids; do
        printf '- **[%s](%s)** — status: `%s`' "$label" "$path" "${status:-unknown}"
        [[ -n "$fids" ]] && printf ' · IDs: `%s`' "$fids"
        printf '\n'
      done < "$tmp_unimpl"
    else
      printf '_No unimplemented specs — all spec features have code coverage. ✓_\n'
    fi

    cat <<SECTION2

---

## Files Without Spec Coverage

Source files in \`src/\` that have no \`SPECIFIES\` in-edge from any spec document.
These are implementation details that may lack business justification.

> Action: Either write a spec for this behavior, or mark it as internal infrastructure.

SECTION2

    if [[ -s "$tmp_unspec" ]]; then
      while IFS=$'\t' read -r id label path; do
        printf '- **[%s](%s)**\n' "$label" "$path"
      done < "$tmp_unspec"
    else
      printf '_All source files have spec coverage. ✓_\n'
    fi

    cat <<SECTION3

---

## Zombie Specs

Specs with \`status: deprecated\` that still have active \`SPECIFIES\` edges
pointing to source code. The code lives on but the spec is gone — this is a
maintenance hazard.

> Action: Either restore the spec, update it to \`status: superseded-by: <new-spec>\`,
> or remove the code.

SECTION3

    if [[ -s "$tmp_zombie" ]]; then
      while IFS=$'\t' read -r spec_id code_id; do
        printf '- **%s** → `%s`\n' "$spec_id" "$code_id"
      done < "$tmp_zombie"
    else
      printf '_No zombie specs. ✓_\n'
    fi

    cat <<SECTION4

---

## Decision Debt

ADR (Architecture Decision Records) in \`draft\` or \`proposed\` status for
more than 30 days. Unresolved decisions block implementation confidence.

> Action: Schedule a decision review, accept or reject, update frontmatter with
> \`adr_status: accepted\` or \`adr_status: rejected\`.

SECTION4

    if [[ -s "$tmp_debt" ]]; then
      while IFS=$'\t' read -r id label path since days; do
        printf '- **[%s](%s)** — proposed: `%s` (%s days ago)\n' "$label" "$path" "$since" "$days"
      done < "$tmp_debt"
    else
      printf '_No stale ADRs. ✓_\n'
    fi

    cat <<SECTION5

---

## Unverified Implementation Claims

Spec nodes with \`status: implemented\` in frontmatter but no git evolution
evidence (no commits referencing their feature IDs). These claims are
self-declared and should be verified.

> Action: Run \`flowai graph chronicle\` to mine git history, or manually verify
> and add \`verified_by: <commit-hash>\` to the spec frontmatter.

SECTION5

    if [[ -s "$tmp_unverified" ]]; then
      while IFS=$'\t' read -r id label path; do
        printf '- **[%s](%s)**\n' "$label" "$path"
      done < "$tmp_unverified"
    else
      printf '_All implementation claims have git evidence. ✓_\n'
    fi

    cat <<REPORT_FOOTER

---

## Recommended Actions

$(if [[ "$total_issues" -eq 0 ]]; then
  printf '1. Graph is clean — no structural issues.\n'
  printf '2. Run `flowai graph update` regularly to keep the graph fresh.\n'
else
  printf '1. Address zombie specs first — they are active maintenance hazards.\n'
  printf "2. Resolve %d unimplemented spec(s) by either implementing or marking as planned.\n" "$unimplemented_count"
  [[ "$debt_count" -gt 0 ]] && printf "3. Schedule review for %d stale ADR(s) — decision debt slows implementation.\n" "$debt_count"
fi)

---

_Generated by FlowAI structural lint engine. Run again after changes: \`flowai graph lint\`_
REPORT_FOOTER

  } > "$report_file"

  log_success "Lint report: $(_graph_rel_path "$report_file")"

  # ── Write machine-readable JSON ───────────────────────────────────────────

  local unimpl_json unspec_json zombie_json debt_json unverified_json
  unimpl_json="$(awk -F'\t' '{print "{\"id\":\""$1"\",\"label\":\""$2"\",\"path\":\""$3"\",\"status\":\""$4"\"}"}' \
    "$tmp_unimpl" | jq -sc '.' 2>/dev/null || echo '[]')"
  unspec_json="$(awk -F'\t' '{print "{\"id\":\""$1"\",\"label\":\""$2"\",\"path\":\""$3"\"}"}' \
    "$tmp_unspec" | jq -sc '.' 2>/dev/null || echo '[]')"
  zombie_json="$(awk -F'\t' '{print "{\"spec\":\""$1"\",\"code\":\""$2"\"}"}' \
    "$tmp_zombie" | jq -sc '.' 2>/dev/null || echo '[]')"
  debt_json="$(awk -F'\t' '{print "{\"id\":\""$1"\",\"label\":\""$2"\",\"path\":\""$3"\",\"since\":\""$4"\",\"days_old\":"$5"}"}' \
    "$tmp_debt" | jq -sc '.' 2>/dev/null || echo '[]')"
  unverified_json="$(awk -F'\t' '{print "{\"id\":\""$1"\",\"label\":\""$2"\",\"path\":\""$3"\"}"}' \
    "$tmp_unverified" | jq -sc '.' 2>/dev/null || echo '[]')"

  jq -n \
    --arg run_at "$built_at" \
    --arg health "$health" \
    --argjson unimplemented "$unimpl_json" \
    --argjson unspecified "$unspec_json" \
    --argjson zombie "$zombie_json" \
    --argjson debt "$debt_json" \
    --argjson unverified "$unverified_json" \
    '{
      "run_at": $run_at,
      "health": $health,
      "counts": {
        "unimplemented_specs": ($unimplemented | length),
        "unspecified_files":   ($unspecified | length),
        "zombie_specs":        ($zombie | length),
        "decision_debt":       ($debt | length),
        "unverified_claims":   ($unverified | length)
      },
      "unimplemented_specs": $unimplemented,
      "unspecified_files":   $unspecified,
      "zombie_specs":        $zombie,
      "decision_debt":       $debt,
      "unverified_claims":   $unverified
    }' > "$json_file"


  # Append to operation log
  flowai_graph_log_append "lint" "health=${health} issues=${total_issues}"

  log_success "Lint complete — ${health}"
  [[ "$total_issues" -gt 0 ]] && log_warn "Run: flowai graph lint --report to read details" || true
  return 0
}
