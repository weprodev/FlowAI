#!/usr/bin/env bash
# Feature-branch + spec.md readiness for flowai start (trunk vs specs/<branch>/spec.md).
# shellcheck shell=bash

# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"
# shellcheck source=src/core/config.sh
source "$FLOWAI_HOME/src/core/config.sh"

# Default trunk branches — work happens on a feature branch with specs/<branch>/.
flowai_spec_is_trunk_branch() {
  local b
  b="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$b" in
    main|master|develop) return 0 ;;
    *) return 1 ;;
  esac
}

# True if spec.md exists and has non-whitespace content.
flowai_spec_md_has_content() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  local body
  body="$(tr -d '[:space:]' < "$f" 2>/dev/null || true)"
  [[ -n "$body" ]]
}

# Path for the current branch feature dir (specs/<branch>/).
flowai_spec_feature_dir_for_branch() {
  local root="$1"
  local branch="$2"
  printf '%s/specs/%s' "$root" "$branch"
}

# Exit 0 = agents have a concrete spec to work with; 1 = start should block or bootstrap.
# No git repo / detached HEAD → 0 (skip guard — e.g. CI temp dirs without git).
flowai_spec_snapshot_ready() {
  local root="${1:-$PWD}"
  local branch
  if ! branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)"; then
    return 0
  fi
  [[ -n "$branch" && "$branch" != "HEAD" ]] || return 0

  if flowai_spec_is_trunk_branch "$branch"; then
    return 1
  fi

  local spec_path
  spec_path="$(flowai_spec_feature_dir_for_branch "$root" "$branch")/spec.md"
  if flowai_spec_md_has_content "$spec_path"; then
    return 0
  fi
  return 1
}

# Create the feature branch from the configured default_branch (init), not from trunk HEAD.
flowai_spec_git_checkout_default_base() {
  local root="$1"
  local base
  base="$(flowai_cfg_default_branch)"
  base="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  [[ -n "$base" ]] || base="main"

  git -C "$root" fetch origin "$base" 2>/dev/null || true

  if git -C "$root" show-ref --verify --quiet "refs/heads/${base}" 2>/dev/null; then
    if ! git -C "$root" checkout "$base" --quiet 2>/dev/null; then
      log_warn "Could not checkout local '${base}' (uncommitted changes?). The new feature branch will be created from your current HEAD."
    else
      log_info "Checked out default branch '${base}' (from .flowai/config.json) before creating the feature branch."
      if git -C "$root" pull --ff-only "origin" "$base" 2>/dev/null || git -C "$root" pull --ff-only 2>/dev/null; then
        log_info "Pulled latest '${base}' from origin."
      else
        log_warn "Could not pull '${base}' (offline, no upstream, or diverged). Continuing with current local '${base}'."
      fi
    fi
    return 0
  fi

  if git -C "$root" show-ref --verify --quiet "refs/remotes/origin/${base}" 2>/dev/null; then
    if git -C "$root" checkout -b "$base" "origin/${base}" --quiet 2>/dev/null || \
       git -C "$root" checkout "$base" --quiet 2>/dev/null; then
      log_info "Created or checked out '${base}' from origin/${base} (default_branch in .flowai/config.json)."
      if git -C "$root" pull --ff-only "origin" "$base" 2>/dev/null || git -C "$root" pull --ff-only 2>/dev/null; then
        log_info "Pulled latest '${base}'."
      else
        log_warn "Could not pull after checkout — using local '${base}' as-is."
      fi
      return 0
    fi
  fi

  log_warn "Default branch '${base}' not found locally or as origin/${base}. Set default_branch in .flowai/config.json or create '${base}'. Creating the feature branch from your current HEAD."
}

# Write a minimal spec template (non-destructive if file exists and has content unless force).
flowai_spec_write_template() {
  local spec_file="$1"
  local title="${2:-New feature}"
  mkdir -p "$(dirname "$spec_file")"
  cat > "$spec_file" <<EOF
# Feature: ${title}

## Overview
Describe the problem, goals, audience, and scope.

The Master Agent will ask what you want to build — answer in this session so the spec can be refined before Plan and Tasks.

## Acceptance criteria
- [ ]

EOF
}

# Interactive: create feature branch + specs dir + spec.md (from trunk). Reuses slug logic.
flowai_spec_wizard_new_branch_from_trunk() {
  local root="${1:-$PWD}"
  printf '\n'
  log_header "Feature branch + spec"
  log_info "Agents need a feature branch and a non-empty specs/<branch>/spec.md before the session runs."
  log_info "Flow: checkout default_branch → pull → new branch → template spec.md → tmux session (Master clarifies the spec)."

  local feature_desc="" slug="" latest_num="" next_num="" suggested="" branch_name=""

  if command -v gum >/dev/null 2>&1; then
    feature_desc="$(gum input --placeholder "Feature name / what you are building (becomes branch slug)...")"
  else
    read -r -p "  Briefly describe what you are building: " feature_desc </dev/tty || true
  fi

  if [[ -z "$feature_desc" ]]; then
    log_error "No description — cannot create a branch."
    return 1
  fi

  slug="$(echo "$feature_desc" | tr '[:upper:]' '[:lower:]' | sed -E -e 's/[^a-z0-9]+/-/g' -e 's/^-+|-+$//g')"
  if [[ -z "$slug" ]]; then
    log_error "Could not derive a branch slug from that description."
    return 1
  fi

  latest_num=$(git -C "$root" branch --format="%(refname:short)" 2>/dev/null | grep '^[0-9]\{3\}-' | sort | tail -n 1 | grep -o '^[0-9]\{3\}' || echo "000")
  next_num=$(printf "%03d" $((10#$latest_num + 1)))
  suggested="${next_num}-${slug}"

  if command -v gum >/dev/null 2>&1; then
    branch_name="$(gum input --value "$suggested" --prompt "Branch name: ")"
  else
    read -r -p "  Branch name [$suggested]: " branch_name </dev/tty || true
    branch_name="${branch_name:-$suggested}"
  fi

  if [[ -z "$branch_name" ]]; then
    log_error "No branch name — aborting."
    return 1
  fi

  flowai_spec_git_checkout_default_base "$root"
  git -C "$root" checkout -b "$branch_name"
  local spec_path
  spec_path="$(flowai_spec_feature_dir_for_branch "$root" "$branch_name")/spec.md"
  flowai_spec_write_template "$spec_path" "$feature_desc"
  log_success "Created branch '$branch_name' and $spec_path"
  log_info "You can refine spec.md as the pipeline runs; continuing to start the session."
  return 0
}

# Interactive: current branch is non-trunk but spec missing or empty — write template.
flowai_spec_bootstrap_current_branch() {
  local root="${1:-$PWD}"
  local branch
  branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 1
  local spec_path
  spec_path="$(flowai_spec_feature_dir_for_branch "$root" "$branch")/spec.md"

  printf '\n'
  log_header "Spec template"
  log_info "Branch: $branch"
  log_info "Required file: $spec_path"

  if [[ -f "$spec_path" ]] && flowai_spec_md_has_content "$spec_path"; then
    return 0
  fi

  local ok_create=1
  if [[ -f "$spec_path" ]]; then
    if command -v gum >/dev/null 2>&1 && [[ -r /dev/tty ]]; then
      gum confirm "spec.md exists but is empty. Overwrite with the FlowAI template?" </dev/tty || ok_create=0
    else
      read -r -p "spec.md is empty. Overwrite with template? [y/N]: " _a </dev/tty 2>/dev/null || true
      [[ "$_a" =~ ^[yY] ]] || ok_create=0
    fi
  else
    if command -v gum >/dev/null 2>&1 && [[ -r /dev/tty ]]; then
      gum confirm "Create specs/${branch}/spec.md from the FlowAI template?" </dev/tty || ok_create=0
    else
      read -r -p "Create spec template now? [Y/n]: " _a </dev/tty 2>/dev/null || true
      [[ -z "$_a" || ! "$_a" =~ ^[nN] ]] || ok_create=0
    fi
  fi

  if [[ "$ok_create" -eq 0 ]]; then
    return 1
  fi

  flowai_spec_write_template "$spec_path" "$branch"
  log_success "Wrote $spec_path"
  return 0
}

# Run after trunk wizard block: if still not ready, guide user (trunk → wizard; else → bootstrap).
flowai_spec_ensure_before_session() {
  local root="${1:-$PWD}"

  if flowai_spec_snapshot_ready "$root"; then
    return 0
  fi

  local branch=""
  branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

  if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
    log_error "Not on a branch with a usable spec. Initialize git, check out a feature branch, and add specs/<branch>/spec.md"
    return 1
  fi

  if flowai_spec_is_trunk_branch "$branch"; then
    log_warn "You are on trunk ($branch). Create a feature branch and spec.md before starting agents."
    if ! flowai_spec_wizard_new_branch_from_trunk "$root"; then
      return 1
    fi
    if ! flowai_spec_snapshot_ready "$root"; then
      log_error "Spec workspace still not ready."
      return 1
    fi
    return 0
  fi

  log_warn "Missing or empty specs/${branch}/spec.md — agents need a filled spec template."
  if ! flowai_spec_bootstrap_current_branch "$root"; then
    log_error "Aborted. Add a non-empty specs/${branch}/spec.md then run: flowai start"
    return 1
  fi

  if ! flowai_spec_snapshot_ready "$root"; then
    log_error "spec.md is still empty — add content and re-run: flowai start"
    return 1
  fi
  return 0
}
