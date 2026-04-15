#!/usr/bin/env bash
# FlowAI — Skills runtime library
# Assembles system prompts by merging role file + assigned skills.
#
# Skill path resolution (4 tiers, first match wins):
#   Tier 1  .flowai/skills/<name>/SKILL.md          (user-installed from GitHub / skills.sh)
#   Tier 2  <skills.paths[]>/<name>/SKILL.md        (project-relative, from config.json)
#   Tier 3  src/skills/<name>/SKILL.md              (bundled with FlowAI)
#   Tier 4  empty string → log_warn                 (not found)
#
# shellcheck shell=bash

# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"
# shellcheck source=src/core/config.sh
source "$FLOWAI_HOME/src/core/config.sh"
# shellcheck source=src/core/graph.sh
source "$FLOWAI_HOME/src/core/graph.sh"
# shellcheck source=src/core/eventlog.sh
source "$FLOWAI_HOME/src/core/eventlog.sh"

_FLOWAI_DEFAULT_SKILLS_JSON="$FLOWAI_HOME/src/core/defaults/skills-role-assignments.json"

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Read skills.paths[] from config.json as newline-separated relative dirs.
# Skips entries that fail flowai_validate_repo_rel_path (logs once per bad entry).
_flowai_cfg_skill_paths() {
  if [[ ! -f "$FLOWAI_DIR/config.json" ]]; then return; fi
  local rel_dir
  while IFS= read -r rel_dir; do
    [[ -z "$rel_dir" ]] && continue
    if ! flowai_validate_repo_rel_path "$rel_dir"; then
      log_warn "Ignoring unsafe skills.paths entry: $rel_dir"
      continue
    fi
    printf '%s\n' "$rel_dir"
  done < <(jq -r '.skills.paths // [] | .[]' "$FLOWAI_DIR/config.json" 2>/dev/null | tr -d '\r')
}

# Map pipeline phase name → role id used in skills.role_assignments.
flowai_skills_effective_role_for_phase() {
  local phase="$1"
  case "$phase" in
    master)
      printf '%s' "master"
      ;;
    *)
      flowai_cfg_pipeline_role "$phase" "backend-engineer"
      ;;
  esac
}

# ─── Resolution ───────────────────────────────────────────────────────────────

# Resolve the SKILL.md path for a given skill name.
# Implements the 4-tier chain described at the top of this file.
flowai_skill_path() {
  local name="$1"

  # Tier 1 — user-installed (per-machine, not in repo)
  local installed="$FLOWAI_DIR/skills/$name/SKILL.md"
  if [[ -f "$installed" ]]; then
    echo "$installed"
    return
  fi

  # Tier 2 — project-relative paths (team-shared, in repo via skills.paths[])
  local rel_dir
  while IFS= read -r rel_dir; do
    [[ -z "$rel_dir" ]] && continue
    local candidate="$PWD/$rel_dir/$name/SKILL.md"
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  done < <(_flowai_cfg_skill_paths)

  # Tier 3 — bundled with FlowAI
  local bundled="$FLOWAI_HOME/src/skills/$name/SKILL.md"
  if [[ -f "$bundled" ]]; then
    echo "$bundled"
    return
  fi

  # Tier 4 — not found
  echo ""
}

# ─── Assignment ───────────────────────────────────────────────────────────────

# List all skill names assigned to a role (from config or defaults file).
flowai_skills_list_for_role() {
  local role="$1"

  # Try config.json first
  local from_config
  from_config="$(jq -r --arg role "$role" \
    '.skills.role_assignments[$role] // [] | .[]' \
    "$FLOWAI_DIR/config.json" 2>/dev/null)"

  if [[ -n "$from_config" ]]; then
    echo "$from_config"
    return
  fi

  # Fall back to bundled defaults JSON (single source of truth with init template)
  if [[ -f "$_FLOWAI_DEFAULT_SKILLS_JSON" ]]; then
    jq -r --arg role "$role" '.[$role] // [] | .[]' "$_FLOWAI_DEFAULT_SKILLS_JSON" 2>/dev/null
  fi
}

# ─── Prompt Builder ───────────────────────────────────────────────────────────

# Build the full system prompt: base role file + injected skills.
# First argument is pipeline phase (e.g. plan, tasks, impl, master); skills resolve via pipeline → role.
flowai_skills_build_prompt() {
  local phase="$1"
  local prompt_file="$2"
  local skill_role
  skill_role="$(flowai_skills_effective_role_for_phase "$phase")"

  # ─── Pipeline Coordination Preamble (role/skill/tool-agnostic) ────────────
  # This block is injected FIRST — before the role content — into EVERY agent
  # prompt. LLMs weight instructions near the top of the context window more
  # heavily. Placing HARD CONSTRAINTS here ensures they are read before any
  # role-specific content that might cause the agent to deviate.
  local prompt="--- [PIPELINE COORDINATION — MANDATORY RULES] ---
You are operating inside FlowAI's multi-agent pipeline. These rules are
MANDATORY and override your default behaviors. Violating them breaks the
pipeline for all agents.

## HARD CONSTRAINTS (read these first)
1. FILE CREATION: You may ONLY write to the OUTPUT FILE specified in your
   PIPELINE DIRECTIVE. Do NOT create any other files. No plan files, no
   summary files, no temporary analysis files.
   PROHIBITED file patterns: *_PLAN.md, *_SUMMARY.md, *_REPORT.md
   The ONLY files you may create or modify:
     spec/master → spec.md | plan → plan.md | tasks → tasks.md
     impl → source code files | review → review.md (+ rejection context when blocking)
2. GRAPH FIRST: When the [FLOWAI KNOWLEDGE GRAPH — CODEBASE MAP] section appears
   right after these rules, it **already embeds** an excerpt of the compiled report —
   **start navigation there** to save tokens. Use index.md and targeted graph.json
   reads (multi-hop / call chains) as described in that block before opening large
   subtrees of source. Do **not** use broad repo search (find / grep / rg / list-dir
   sweeps) to *discover* layout or ownership — that duplicates the graph and wastes
   context. After the graph names specific files, read those files; narrow search
   inside known paths is OK. Open the on-disk GRAPH_REPORT file only if you need
   detail beyond the embedded excerpt.
3. SPEC IS TRUTH: The specification (spec.md) is the AUTHORITATIVE single
   source of truth. Every decision traces back to it. When any artifact
   conflicts with spec.md, the spec wins. Before completing your work,
   verify alignment against spec.md acceptance criteria.

## Orchestration
- The Master Agent is the central orchestrator of the entire pipeline.
  All downstream agents report to Master, and Master controls phase transitions.
- Your phase script controls when you start and what upstream signals to wait for.
  You do NOT need to check signal files yourself — the orchestrator handles this.
- When you finish your work, the orchestrator will verify your output.
  Follow the APPROVAL PROTOCOL in your PIPELINE DIRECTIVE if one is provided.

## Task Tracking
- If your phase works with a task checklist (tasks.md), mark tasks complete as
  you finish each one. Work through them one at a time.
- If you encounter a problem you cannot resolve, raise a blocker in the output
  artifact under a '## Blockers' heading and do NOT proceed past it.

## Pipeline Awareness
- The [PIPELINE EVENT LOG] section below shows what other agents have done.
  Use it to understand progress, approvals, and rejections.
---"

  # Knowledge graph: immediately after HARD CONSTRAINTS (before role + skills) so
  # the map is high in the context window — reduces blind search and token waste.
  if flowai_graph_is_enabled && flowai_graph_exists; then
    local graph_block
    graph_block="$(flowai_graph_context_block)"
    if [[ -n "$graph_block" ]]; then
      prompt="${prompt}${graph_block}"
    fi
  fi

  # ─── Role + Directive + Artifact Boundary ────────────────────────────────
  if [[ -f "$prompt_file" ]]; then
    prompt="${prompt}

$(cat "$prompt_file")"
  fi

  # Inject constitution if present
  local constitution=""
  if declare -f flowai_specify_constitution_path >/dev/null 2>&1; then
    constitution="$(flowai_specify_constitution_path "$PWD")"
  fi
  if [[ -n "$constitution" ]] && [[ -f "$constitution" ]]; then
    prompt="${prompt}

--- [PROJECT CONSTITUTION] ---
$(cat "$constitution")
---"
  fi

  # Inject pipeline event log context (cross-agent visibility)
  local event_context
  event_context="$(flowai_event_format_for_prompt 30)"
  if [[ -n "$event_context" ]]; then
    prompt="${prompt}

--- [PIPELINE EVENT LOG] ---
Recent pipeline activity (most recent last). Use this to understand what
other agents have done, what has been approved/rejected, and overall progress.

${event_context}
---"
  fi

  # Inject assigned skills
  local skill_name skill_file
  while IFS= read -r skill_name; do
    [[ -z "$skill_name" ]] && continue
    skill_file="$(flowai_skill_path "$skill_name")"
    if [[ -n "$skill_file" ]]; then
      prompt="${prompt}

--- [SKILL: ${skill_name}] ---
$(cat "$skill_file")
---"
    else
      log_warn "Skill not found: $skill_name (run: flowai skill add)"
    fi
  done < <(flowai_skills_list_for_role "$skill_role")

  printf '%s' "$prompt"
}

# ─── Discovery ────────────────────────────────────────────────────────────────

# List all available skill names (installed + project-relative + bundled, deduplicated).
flowai_skills_all() {
  {
    # Tier 1 — installed
    if [[ -d "$FLOWAI_DIR/skills" ]]; then
      find "$FLOWAI_DIR/skills" -maxdepth 2 -name "SKILL.md" | \
        while IFS= read -r f; do basename "$(dirname "$f")"; done
    fi

    # Tier 2 — project-relative paths
    local rel_dir
    while IFS= read -r rel_dir; do
      [[ -z "$rel_dir" ]] && continue
      local abs_dir="$PWD/$rel_dir"
      if [[ -d "$abs_dir" ]]; then
        find "$abs_dir" -maxdepth 2 -name "SKILL.md" | \
          while IFS= read -r f; do basename "$(dirname "$f")"; done
      fi
    done < <(_flowai_cfg_skill_paths)

    # Tier 3 — bundled
    if [[ -d "$FLOWAI_HOME/src/skills" ]]; then
      find "$FLOWAI_HOME/src/skills" -maxdepth 2 -name "SKILL.md" | \
        while IFS= read -r f; do basename "$(dirname "$f")"; done
    fi
  } | sort -u
}

# True if a skill exists anywhere in the resolution chain.
flowai_skill_exists() {
  local name="$1"
  [[ -n "$(flowai_skill_path "$name")" ]]
}

# True if a skill is user-installed (Tier 1 only).
flowai_skill_is_installed() {
  local name="$1"
  [[ -f "$FLOWAI_DIR/skills/$name/SKILL.md" ]]
}
