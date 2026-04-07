#!/usr/bin/env bash
# FlowAI — Skills runtime library
# Assembles system prompts by merging role file + assigned skills.
# Priority: installed (.flowai/skills/) > bundled (src/skills/)
# shellcheck shell=bash

# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"
# shellcheck source=src/core/config.sh
source "$FLOWAI_HOME/src/core/config.sh"

_FLOWAI_DEFAULT_SKILLS_JSON="$FLOWAI_HOME/src/core/defaults/skills-role-assignments.json"

# Map pipeline phase name → role id used in skills.role_assignments (matches flowai_phase_resolve_role_prompt).
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

# Resolve the SKILL.md path for a given skill name.
# Returns installed path first, then bundled, then empty.
flowai_skill_path() {
  local name="$1"
  local installed="$FLOWAI_DIR/skills/$name/SKILL.md"
  local bundled="$FLOWAI_HOME/src/skills/$name/SKILL.md"

  if [[ -f "$installed" ]]; then
    echo "$installed"
  elif [[ -f "$bundled" ]]; then
    echo "$bundled"
  else
    echo ""
  fi
}

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

# Build the full system prompt: base role file + injected skills.
# First argument is pipeline phase (e.g. plan, tasks, impl, master); skills resolve via pipeline → role.
flowai_skills_build_prompt() {
  local phase="$1"
  local prompt_file="$2"
  local skill_role
  skill_role="$(flowai_skills_effective_role_for_phase "$phase")"

  local prompt=""
  if [[ -f "$prompt_file" ]]; then
    prompt="$(cat "$prompt_file")"
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

# List all available skill names (installed + bundled, deduplicated).
flowai_skills_all() {
  {
    # Installed
    if [[ -d "$FLOWAI_DIR/skills" ]]; then
      find "$FLOWAI_DIR/skills" -maxdepth 2 -name "SKILL.md" | \
        while IFS= read -r f; do basename "$(dirname "$f")"; done
    fi
    # Bundled
    if [[ -d "$FLOWAI_HOME/src/skills" ]]; then
      find "$FLOWAI_HOME/src/skills" -maxdepth 2 -name "SKILL.md" | \
        while IFS= read -r f; do basename "$(dirname "$f")"; done
    fi
  } | sort -u
}

# True if a skill exists (installed or bundled).
flowai_skill_exists() {
  local name="$1"
  [[ -n "$(flowai_skill_path "$name")" ]]
}

# True if a skill is user-installed (not just bundled).
flowai_skill_is_installed() {
  local name="$1"
  [[ -f "$FLOWAI_DIR/skills/$name/SKILL.md" ]]
}
