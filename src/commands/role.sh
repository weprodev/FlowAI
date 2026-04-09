#!/usr/bin/env bash
# FlowAI — role management command
# Manage project-local role prompt overrides.
#
# Role prompt resolution (see src/core/phase.sh for full chain):
#   Tier 1  .flowai/roles/<phase>.md          — file drop by phase name
#   Tier 2  .flowai/roles/<role>.md           — file drop by role name
#   Tier 3  config.json roles[<role>].prompt_file — project-relative file
#   Tier 4  bundled src/roles/<role>.md
#
# Usage: flowai role [list|edit|set-prompt|reset] [args...]
# shellcheck shell=bash

set -euo pipefail

# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"
# shellcheck source=src/core/config.sh
source "$FLOWAI_HOME/src/core/config.sh"

# ─── Helpers ──────────────────────────────────────────────────────────────────

_role_require_flowai_dir() {
  if [[ ! -f "$FLOWAI_DIR/config.json" ]]; then
    log_error "Not a FlowAI project — run: flowai init"
    exit 1
  fi
}

# List all role names from the bundled src/roles/ directory.
_role_bundled_names() {
  [[ -d "$FLOWAI_HOME/src/roles" ]] || return 0
  find "$FLOWAI_HOME/src/roles" -maxdepth 1 -name "*.md" | \
    while IFS= read -r f; do basename "$f" .md; done | sort
}

# Return the active override type for a role, or "bundled" if none.
_role_override_type() {
  local role="$1"

  # Tier 1–2 (phase.sh): .flowai/roles/<role>.md — same filename as bundled role key
  if [[ -f "$FLOWAI_DIR/roles/${role}.md" ]]; then
    printf 'local-file'
    return
  fi

  # Tier 3: config prompt_file (ignored here if path is unsafe — matches resolver)
  if [[ -f "$FLOWAI_DIR/config.json" ]]; then
    local pf
    pf="$(jq -r --arg r "$role" '.roles[$r].prompt_file // empty' "$FLOWAI_DIR/config.json" 2>/dev/null)"
    if [[ -n "$pf" ]] && flowai_validate_repo_rel_path "$pf"; then
      printf 'prompt_file (%s)' "$pf"
      return
    fi
  fi

  printf 'bundled'
}

# Write prompt_file key for a role in config.json (idempotent).
# Errors if the role is not already defined in config.json — avoids creating
# skeleton entries missing tool/model that would fail config validation.
_role_config_set_prompt_file() {
  local role="$1" rel_path="$2"

  rel_path="$(flowai_normalize_repo_rel_path "$rel_path")"
  if ! flowai_validate_repo_rel_path "$rel_path"; then
    log_error "prompt_file must be project-relative without '..': $rel_path"
    return 1
  fi

  # Safety: only write into an existing role entry
  local role_exists
  role_exists="$(jq -r --arg r "$role" '.roles[$r] // empty' "$FLOWAI_DIR/config.json" 2>/dev/null)"
  if [[ -z "$role_exists" ]]; then
    log_error "Role '$role' is not defined in .flowai/config.json roles block."
    log_info "Add it first: \"$role\": { \"tool\": \"gemini\", \"model\": \"...\" }"
    return 1
  fi

  local tmp
  tmp="$(mktemp)"
  jq --arg r "$role" --arg p "$rel_path" '
    .roles[$r].prompt_file = $p
  ' "$FLOWAI_DIR/config.json" > "$tmp" && mv "$tmp" "$FLOWAI_DIR/config.json" || rm -f "$tmp"
}

# Remove prompt_file key for a role from config.json.
_role_config_unset_prompt_file() {
  local role="$1"
  local tmp
  tmp="$(mktemp)"
  jq --arg r "$role" '
    if .roles[$r] then .roles[$r] |= del(.prompt_file) else . end
  ' "$FLOWAI_DIR/config.json" > "$tmp" && mv "$tmp" "$FLOWAI_DIR/config.json" || rm -f "$tmp"
}

# ─── list ─────────────────────────────────────────────────────────────────────

cmd_role_list() {
  _role_require_flowai_dir

  log_header "Roles"
  printf '\n'

  while IFS= read -r role; do
    [[ -z "$role" ]] && continue
    local override
    override="$(_role_override_type "$role")"
    if [[ "$override" == "bundled" ]]; then
      log_info "  $role  (bundled)"
    else
      log_success "  $role  → $override"
    fi
  done < <(_role_bundled_names)

  printf '\n'
  printf '  %s\n' "Options: flowai role edit <role> | flowai role set-prompt <role> <path> | flowai role reset <role>"
  printf '\n'
}

# ─── edit ─────────────────────────────────────────────────────────────────────

cmd_role_edit() {
  _role_require_flowai_dir

  local target_role="${1:-}"

  if [[ -z "$target_role" ]]; then
    if ! command -v gum >/dev/null 2>&1; then
      log_error "gum required for interactive mode. Usage: flowai role edit <role>"
      exit 1
    fi
    local roles
    mapfile -t roles < <(_role_bundled_names)
    target_role="$(gum choose --header "Select role to edit:" "${roles[@]}")"
  fi

  [[ -z "$target_role" ]] && { log_error "No role selected."; exit 1; }

  local dest="$FLOWAI_DIR/roles/${target_role}.md"
  local src="$FLOWAI_HOME/src/roles/${target_role}.md"

  if [[ ! -f "$src" ]]; then
    log_error "No bundled role found: ${target_role}.md"
    exit 1
  fi

  if [[ -f "$dest" ]]; then
    log_warn "Override already exists: $dest"
    if command -v gum >/dev/null 2>&1; then
      gum confirm "Re-open in \$EDITOR?" || exit 0
    fi
  else
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    log_success "Copied bundled role → $dest"
  fi

  local my_editor="${EDITOR:-vi}"
  command -v "$my_editor" >/dev/null 2>&1 || my_editor="vi"
  log_info "Opening in $my_editor..."
  "$my_editor" "$dest" </dev/tty >/dev/tty 2>&1 || true
  log_success "Saved: $dest (Tier 1/2 override active)"
}

# ─── set-prompt ───────────────────────────────────────────────────────────────

cmd_role_set_prompt() {
  _role_require_flowai_dir

  local target_role="${1:-}"
  local rel_path="${2:-}"

  if [[ -z "$target_role" ]] || [[ -z "$rel_path" ]]; then
    if command -v gum >/dev/null 2>&1; then
      if [[ -z "$target_role" ]]; then
        local roles
        mapfile -t roles < <(_role_bundled_names)
        target_role="$(gum choose --header "Select role:" "${roles[@]}")"
      fi
      [[ -z "$target_role" ]] && { log_error "No role selected."; exit 1; }
      if [[ -z "$rel_path" ]]; then
        rel_path="$(gum input --placeholder "docs/roles/${target_role}.md")"
      fi
    else
      log_error "Usage: flowai role set-prompt <role> <project-relative-path>"
      exit 1
    fi
  fi

  [[ -z "$rel_path" ]] && { log_error "No path entered."; exit 1; }

  rel_path="$(flowai_normalize_repo_rel_path "$rel_path")"
  if ! flowai_validate_repo_rel_path "$rel_path"; then
    log_error "prompt_file must be project-relative without '..': $rel_path"
    exit 1
  fi

  if [[ ! -f "$PWD/$rel_path" ]]; then
    log_warn "File not found yet: $PWD/$rel_path"
    if command -v gum >/dev/null 2>&1; then
      gum confirm "Register anyway (create the file before running)?" || exit 0
    fi
  fi

  _role_config_set_prompt_file "$target_role" "$rel_path"
  log_success "Set roles.${target_role}.prompt_file = \"$rel_path\""
  log_info "Tier 3 override active. Remove with: flowai role reset $target_role"
}

# ─── reset ────────────────────────────────────────────────────────────────────

cmd_role_reset() {
  _role_require_flowai_dir

  local target_role="${1:-}"

  if [[ -z "$target_role" ]]; then
    if ! command -v gum >/dev/null 2>&1; then
      log_error "gum required for interactive mode. Usage: flowai role reset <role>"
      exit 1
    fi
    local roles
    mapfile -t roles < <(_role_bundled_names)
    target_role="$(gum choose --header "Select role to reset:" "${roles[@]}")"
  fi

  [[ -z "$target_role" ]] && { log_error "No role selected."; exit 1; }

  local removed=0

  # Remove Tier 1 / 2 file drop
  local local_file="$FLOWAI_DIR/roles/${target_role}.md"
  if [[ -f "$local_file" ]]; then
    rm -f "$local_file"
    log_success "Removed local override: $local_file"
    removed=$((removed + 1))
  fi

  # Remove Tier 3 config key
  if [[ -f "$FLOWAI_DIR/config.json" ]]; then
    local pf
    pf="$(jq -r --arg r "$target_role" '.roles[$r].prompt_file // empty' "$FLOWAI_DIR/config.json" 2>/dev/null)"
    if [[ -n "$pf" ]]; then
      _role_config_unset_prompt_file "$target_role"
      log_success "Removed prompt_file config key for: $target_role"
      removed=$((removed + 1))
    fi
  fi

  if [[ $removed -eq 0 ]]; then
    log_info "No overrides found for '$target_role' — already using bundled."
  else
    log_info "Role '$target_role' now resolves to bundled: $FLOWAI_HOME/src/roles/${target_role}.md"
  fi
}

# ─── Entry point ──────────────────────────────────────────────────────────────

subcmd="${1:-}"
shift || true

case "$subcmd" in
  list|"")    cmd_role_list ;;
  edit)       cmd_role_edit "$@" ;;
  set-prompt) cmd_role_set_prompt "$@" ;;
  reset)      cmd_role_reset "$@" ;;
  *)
    log_error "Unknown role subcommand: $subcmd"
    printf 'Usage: flowai role [list|edit|set-prompt|reset]\n'
    exit 1
    ;;
esac
