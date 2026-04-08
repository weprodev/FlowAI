#!/usr/bin/env bash
# FlowAI — skill management command
# Usage: flowai skill [list|add|apply|remove] [args...]
# shellcheck shell=bash

set -euo pipefail

# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"
# shellcheck source=src/core/config.sh
source "$FLOWAI_HOME/src/core/config.sh"
# shellcheck source=src/core/skills.sh
source "$FLOWAI_HOME/src/core/skills.sh"

# ─── Helpers ──────────────────────────────────────────────────────────────────

_skill_require_flowai_dir() {
  if [[ ! -f "$FLOWAI_DIR/config.json" ]]; then
    log_error "Not a FlowAI project — run: flowai init"
    exit 1
  fi
}

_skill_require_node() {
  if ! command -v node >/dev/null 2>&1; then
    log_error "Node.js is required to install skills from skills.sh."
    printf '%s\n' "  Install: brew install node   (or https://nodejs.org)"
    exit 1
  fi
}

_skill_bundled_list() {
  if [[ -d "$FLOWAI_HOME/src/skills" ]]; then
    find "$FLOWAI_HOME/src/skills" -maxdepth 2 -name "SKILL.md" | \
      while IFS= read -r f; do basename "$(dirname "$f")"; done | sort
  fi
}

_skill_installed_list() {
  if [[ -d "$FLOWAI_DIR/skills" ]]; then
    find "$FLOWAI_DIR/skills" -maxdepth 2 -name "SKILL.md" | \
      while IFS= read -r f; do basename "$(dirname "$f")"; done | sort
  fi
}

_skill_roles_for_skill() {
  local target="$1"
  jq -r --arg skill "$target" \
    '.skills.role_assignments // {} | to_entries[] | select(.value[] == $skill) | .key' \
    "$FLOWAI_DIR/config.json" 2>/dev/null | sort | tr '\n' ',' | sed 's/,$//'
}

_skill_config_add_assignment() {
  local skill="$1" role="$2"
  local tmp
  tmp="$(mktemp)"
  jq --arg skill "$skill" --arg role "$role" '
    .skills.role_assignments[$role] //= [] |
    if (.skills.role_assignments[$role] | index($skill)) == null then
      .skills.role_assignments[$role] += [$skill]
    else . end
  ' "$FLOWAI_DIR/config.json" > "$tmp" && mv "$tmp" "$FLOWAI_DIR/config.json" || rm -f "$tmp"
}

_skill_config_remove_assignment() {
  local skill="$1"
  local tmp
  tmp="$(mktemp)"
  jq --arg skill "$skill" '
    .skills.role_assignments //= {} |
    .skills.role_assignments |= (to_entries |
      map(.value -= [$skill]) | from_entries)
  ' "$FLOWAI_DIR/config.json" > "$tmp" && mv "$tmp" "$FLOWAI_DIR/config.json" || rm -f "$tmp"
}

# ─── list ─────────────────────────────────────────────────────────────────────

cmd_skill_list() {
  _skill_require_flowai_dir

  log_header "Skills"

  printf '\n %s\n' "Bundled"
  local bundled_count=0
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    bundled_count=$((bundled_count + 1))
    local roles
    roles="$(_skill_roles_for_skill "$name")"
    if [[ -n "$roles" ]]; then
      log_success "  $name  → $roles"
    else
      log_info "  $name  (unassigned)"
    fi
  done < <(_skill_bundled_list)
  [[ $bundled_count -eq 0 ]] && printf '  %s\n' "— none"

  printf '\n %s\n' "Installed"
  local installed_count=0
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    installed_count=$((installed_count + 1))
    local roles
    roles="$(_skill_roles_for_skill "$name")"
    if [[ -n "$roles" ]]; then
      log_success "  $name  → $roles"
    else
      log_info "  $name  (unassigned)"
    fi
  done < <(_skill_installed_list)
  [[ $installed_count -eq 0 ]] && printf '  — none. Try: %s\n' "flowai skill add"
  printf '\n'
}

# ─── add ──────────────────────────────────────────────────────────────────────

# Top skills catalog for interactive browsing
_SKILL_CATALOG=(
  "obra/superpowers/systematic-debugging|51.8K|Structured debugging methodology"
  "obra/superpowers/test-driven-development|43.8K|TDD process and practices"
  "obra/superpowers/requesting-code-review|42.5K|How to request effective reviews"
  "obra/superpowers/executing-plans|41.3K|Executing implementation plans precisely"
  "obra/superpowers/verification-before-completion|34.8K|Verify work before marking done"
  "obra/superpowers/writing-plans|33.6K|How to write clear implementation plans"
  "obra/superpowers/subagent-driven-development|36.7K|Dispatch and coordinate sub-agents"
  "obra/superpowers/finishing-a-development-branch|30.2K|Wrap up a branch cleanly"
  "obra/superpowers/dispatching-parallel-agents|32.2K|Run agents in parallel"
  "obra/superpowers/using-git-worktrees|32.3K|Parallel work via git worktrees"
)

_skill_download() {
  local owner_repo_skill="$1"   # e.g. obra/superpowers/systematic-debugging
  local name="${owner_repo_skill##*/}"
  local owner_repo="${owner_repo_skill%/*}"
  local dest="$FLOWAI_DIR/skills/$name"

  mkdir -p "$dest"

  # Try GitHub raw first (if the repo has skills/ subdirectory layout)
  local raw_url="https://raw.githubusercontent.com/${owner_repo}/main/skills/${name}/SKILL.md"
  if curl -fsSL "$raw_url" -o "$dest/SKILL.md" 2>/dev/null; then
    log_success "Downloaded $name from $owner_repo"
    return 0
  fi

  # Fallback: use npx skills add (requires Node)
  _skill_require_node
  log_info "Fetching $name via npx skills..."
  if (cd "$FLOWAI_DIR/skills" && npx --yes skills add "$owner_repo_skill" 2>/dev/null); then
    log_success "Installed $name"
    return 0
  fi

  log_error "Could not download skill: $owner_repo_skill"
  return 1
}

cmd_skill_add() {
  _skill_require_flowai_dir
  # Explicit install from Context7 / skills.sh compatible GitHub paths (same layout as skills.sh catalog).
  if [[ "${1:-}" == "context7" ]]; then
    shift
    local c7_target="${1:-}"
    if [[ -z "$c7_target" ]]; then
      log_error "Usage: flowai skill add context7 <owner/repo/skill-name>"
      printf '%s\n' "  Browse: https://context7.com/skills  ·  https://skills.sh"
      exit 1
    fi
    log_info "Installing skill path (GitHub layout; listed on Context7 & skills.sh): $c7_target"
    _skill_download "$c7_target"
    local c7_name="${c7_target##*/}"
    if [[ -t 0 ]] && command -v gum >/dev/null 2>&1; then
      if gum confirm "Apply $c7_name to a role now?"; then
        cmd_skill_apply "$c7_name"
      fi
    fi
    return
  fi

  local target="${1:-}"

  if [[ -n "$target" ]]; then
    # Direct install
    _skill_download "$target"
    local name="${target##*/}"
    if [[ -t 0 ]] && command -v gum >/dev/null 2>&1; then
      if gum confirm "Apply $name to a role now?"; then
        cmd_skill_apply "$name"
      fi
    fi
    return
  fi

  # Interactive mode
  if ! command -v gum >/dev/null 2>&1; then
    log_error "gum is required for interactive mode. Install: brew install gum"
    log_info "Or use: flowai skill add <owner/repo/skill-name>"
    exit 1
  fi

  local source_choice
  source_choice="$(gum choose --header "Select skill source (see https://skills.sh / https://context7.com/skills):" \
    "skills.sh (recommended)" "Context7 / GitHub path" "Paste GitHub path")"

  local skill_path=""
  if [[ "$source_choice" == "Paste GitHub path" ]]; then
    skill_path="$(gum input --placeholder "owner/repo/skill-name")"
  elif [[ "$source_choice" == "Context7 / GitHub path" ]]; then
    log_info "Paste a path from https://context7.com/skills (same repo layout as skills.sh)."
    skill_path="$(gum input --placeholder "owner/repo/skill-name")"
  else
    # Show catalog
    local catalog_display=()
    for entry in "${_SKILL_CATALOG[@]}"; do
      local path install_count desc
      path="$(echo "$entry" | cut -d'|' -f1)"
      install_count="$(echo "$entry" | cut -d'|' -f2)"
      desc="$(echo "$entry" | cut -d'|' -f3)"
      catalog_display+=("${path##*/}  (${install_count} installs) — ${desc}")
    done

    local selection
    selection="$(gum choose --header "Select a skill:" "${catalog_display[@]}" "Custom — enter path")"

    if [[ "$selection" == Custom* ]]; then
      skill_path="$(gum input --placeholder "owner/repo/skill-name")"
    else
      local skill_name
      skill_name="$(echo "$selection" | awk '{print $1}')"
      # Find matching entry
      for entry in "${_SKILL_CATALOG[@]}"; do
        if [[ "${entry##*/}" == "$skill_name"* ]]; then
          skill_path="${entry%%|*}"
          break
        fi
      done
    fi
  fi

  [[ -z "$skill_path" ]] && { log_error "No skill selected."; exit 1; }

  _skill_download "$skill_path"
  local name="${skill_path##*/}"

  if gum confirm "Apply $name to a role now?"; then
    cmd_skill_apply "$name"
  fi
}

# ─── apply ────────────────────────────────────────────────────────────────────

cmd_skill_apply() {
  _skill_require_flowai_dir
  local target_skill="${1:-}"

  local all_skills
  mapfile -t all_skills < <(flowai_skills_all)

  if [[ -z "$target_skill" ]]; then
    if ! command -v gum >/dev/null 2>&1; then
      log_error "gum required for interactive mode."
      exit 1
    fi
    target_skill="$(gum choose --header "Select skill to apply:" "${all_skills[@]}")"
  fi

  [[ -z "$target_skill" ]] && { log_error "No skill selected."; exit 1; }

  if ! flowai_skill_exists "$target_skill"; then
    log_error "Skill not found: $target_skill"
    exit 1
  fi

  # Show current assignments
  local current_roles
  current_roles="$(_skill_roles_for_skill "$target_skill")"
  if [[ -n "$current_roles" ]]; then
    log_warn "$target_skill is already assigned to: $current_roles"
    if command -v gum >/dev/null 2>&1; then
      gum confirm "Override/extend assignment?" || exit 0
    fi
  fi

  local roles
  roles="$(jq -r '.roles | keys[]' "$FLOWAI_DIR/config.json" 2>/dev/null | sort)"
  mapfile -t role_list < <(echo "$roles")

  if command -v gum >/dev/null 2>&1; then
    local selected_roles
    selected_roles="$(gum choose --no-limit --header "Select roles to assign '$target_skill' to:" "${role_list[@]}")"
    while IFS= read -r role; do
      [[ -z "$role" ]] && continue
      _skill_config_add_assignment "$target_skill" "$role"
      log_success "Assigned $target_skill → $role"
    done <<< "$selected_roles"
  else
    log_info "Available roles: ${role_list[*]}"
    read -r -p "Enter role name: " role_name
    _skill_config_add_assignment "$target_skill" "$role_name"
    log_success "Assigned $target_skill → $role_name"
  fi
}

# ─── remove ───────────────────────────────────────────────────────────────────

cmd_skill_remove() {
  _skill_require_flowai_dir

  local installed_skills
  mapfile -t installed_skills < <(_skill_installed_list)

  if [[ ${#installed_skills[@]} -eq 0 ]]; then
    log_info "No installed skills to remove. (Bundled skills cannot be removed.)"
    return 0
  fi

  local target_skill
  if command -v gum >/dev/null 2>&1; then
    target_skill="$(gum choose --header "Select skill to remove:" "${installed_skills[@]}")"
  else
    printf '%s\n' "${installed_skills[@]}"
    read -r -p "Skill name to remove: " target_skill
  fi

  [[ -z "$target_skill" ]] && exit 0

  local current_roles
  current_roles="$(_skill_roles_for_skill "$target_skill")"
  if [[ -n "$current_roles" ]]; then
    printf '\n'
    log_warn "Skill '$target_skill' is assigned to: $current_roles"
    # Check if bundled version exists as fallback
    if [[ -f "$FLOWAI_HOME/src/skills/$target_skill/SKILL.md" ]]; then
      log_info "A bundled version exists and will be used as fallback."
    else
      log_warn "No bundled fallback exists — role(s) will lose this skill."
    fi
    printf '\n'
  fi

  if command -v gum >/dev/null 2>&1; then
    gum confirm "Remove $target_skill?" || exit 0
  else
    read -r -p "Confirm removal of $target_skill? [y/N]: " ans
    [[ "$ans" =~ ^[yY] ]] || exit 0
  fi

  rm -rf "$FLOWAI_DIR/skills/$target_skill"
  _skill_config_remove_assignment "$target_skill"
  log_success "Removed $target_skill"
}

# ─── Entry point ──────────────────────────────────────────────────────────────

subcmd="${1:-}"
shift || true

case "$subcmd" in
  list|"") cmd_skill_list ;;
  add)     cmd_skill_add "$@" ;;
  apply)   cmd_skill_apply "$@" ;;
  remove)  cmd_skill_remove ;;
  *)
    log_error "Unknown skill subcommand: $subcmd"
    printf 'Usage: flowai skill [list|add|apply|remove]\n'
    exit 1
    ;;
esac
