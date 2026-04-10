#!/usr/bin/env bash
# FlowAI — initialize .flowai in the current repository
# Usage: flowai init [--with-specify]   (Spec Kit bootstrap is optional — can download tools)
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/bootstrap/specify.sh"

if ! command -v jq >/dev/null 2>&1; then
  log_error "jq is required. Install jq (e.g. brew install jq) and re-run flowai init."
  exit 1
fi

log_info "Initializing FlowAI in $PWD..."

FLOWAI_DIR="$PWD/.flowai"
reconfigure="no"

if [[ -d "$FLOWAI_DIR" ]] && [[ -f "$FLOWAI_DIR/config.json" ]]; then
  if ! jq -e . "$FLOWAI_DIR/config.json" >/dev/null 2>&1; then
    log_error "Invalid JSON in $FLOWAI_DIR/config.json — fix syntax before continuing."
    exit 1
  fi
  
  if [[ -t 0 ]] && [[ "${FLOWAI_TESTING:-0}" != "1" ]]; then
    printf "\n"
    log_warn "FlowAI is already configured in this directory."
    read -r -p "Do you want to re-configure it from scratch? [y/N]: " ans_reconfig
    if [[ "$ans_reconfig" =~ ^[Yy]$ ]]; then
      reconfigure="yes"
    else
      log_warn ".flowai already exists — leaving config in place."
    fi
  else
    log_warn ".flowai already exists — leaving config in place."
  fi
fi

if [[ ! -d "$FLOWAI_DIR" ]] || [[ ! -f "$FLOWAI_DIR/config.json" ]] || [[ "$reconfigure" == "yes" ]]; then
  if [[ -f "$PWD/.specify/memory/setup.json" ]] && [[ "$reconfigure" == "no" ]]; then
    mkdir -p "$FLOWAI_DIR/roles"
    mkdir -p "$FLOWAI_DIR/signals"
    mkdir -p "$FLOWAI_DIR/launch"
    mkdir -p "$FLOWAI_DIR/wiki"
    mkdir -p "$FLOWAI_DIR/wiki/cache"
    log_info "Migrating legacy .specify/memory/setup.json → .flowai/config.json"
    cp "$PWD/.specify/memory/setup.json" "$FLOWAI_DIR/config.json"
    jq '.' "$FLOWAI_DIR/config.json" >/dev/null
    log_success "Wrote $FLOWAI_DIR/config.json"
  else
    # Bootstrap Spec Kit while the tree is still empty-ish
    if [[ "${FLOWAI_TESTING:-0}" != "1" ]] && ! flowai_specify_is_present "$PWD"; then
      log_info "Bootstrapping Spec Kit (requires uv)..."
      flowai_specify_ensure "$PWD" || true
    fi
    mkdir -p "$FLOWAI_DIR/roles"
    mkdir -p "$FLOWAI_DIR/signals"
    mkdir -p "$FLOWAI_DIR/launch"
    mkdir -p "$FLOWAI_DIR/wiki"
    mkdir -p "$FLOWAI_DIR/wiki/cache"

    _mc="$FLOWAI_HOME/models-catalog.json"
    _gdef="gemini-2.5-pro"
    _cdef="sonnet"
    
    declare -a tool_names=()
    if [[ -f "$_mc" ]]; then
      while IFS= read -r t_name; do
        [[ -n "$t_name" ]] && tool_names+=("$t_name")
      done < <(jq -r '.tools | keys[]' "$_mc")
      
      _gdef="$(jq -r '.tools.gemini.default_id // "gemini-2.5-pro"' "$_mc")"
      _cdef="$(jq -r '.tools.claude.default_id // "sonnet"' "$_mc")"
    fi
    
    if [ ${#tool_names[@]} -eq 0 ]; then
      tool_names=("gemini" "claude" "cursor")
    fi

    # Wizard Variables Default Values
    wizard_branch="main"
    wizard_tool="${tool_names[0]}"
    wizard_auto_approve="false"

    # Interactive Setup Wizard
    if [[ -t 0 ]] && [[ "${FLOWAI_TESTING:-0}" != "1" ]]; then
      log_header "FlowAI Configuration Wizard"
      
      # 1. Default Branch
      printf "Select your default branch (used for new spec kit tasks):\n"
      printf "  1) main\n"
      printf "  2) master\n"
      printf "  3) develop\n"
      printf "  4) Custom...\n"
      read -r -p "Enter Choice (1-4) [1]: " ans_b
      case "$ans_b" in
        2) wizard_branch="master" ;;
        3) wizard_branch="develop" ;;
        4) 
           read -r -p "     Enter custom branch name: " c_branch
           [[ -n "$c_branch" ]] && wizard_branch="$c_branch"
           ;;
        *) wizard_branch="main" ;;
      esac
      printf "\n"
      
      # 2. Primary Tool
      printf "Select your primary AI Provider for roles (Master, Plan, Review):\n"
      i=1
      for t in "${tool_names[@]}"; do
        printf "  %d) %s\n" "$i" "$t"
        i=$((i + 1))
      done
      read -r -p "Enter Choice (1-${#tool_names[@]}) [1]: " ans_t
      
      if [[ "$ans_t" =~ ^[0-9]+$ ]] && [[ "$ans_t" -ge 1 ]] && [[ "$ans_t" -le "${#tool_names[@]}" ]]; then
        wizard_tool="${tool_names[$(( ans_t - 1 ))]}"
      else
        wizard_tool="${tool_names[0]}"
      fi
      printf "\n"

      # 3. Auto Approve
      read -r -p "Enable auto-approval for safe shell commands? (Recommended: N) [y/N]: " ans_aa
      if [[ "$ans_aa" =~ ^[Yy]$ ]]; then
        wizard_auto_approve="true"
      fi
      printf "\n"
    fi

    # Determine default model based on selection
    if [[ -f "$_mc" ]]; then
      wizard_model="$(jq -r --arg t "$wizard_tool" '.tools[$t].default_id // "default"' "$_mc")"
    else
      if [ "$wizard_tool" = "gemini" ]; then wizard_model="$_gdef";
      elif [ "$wizard_tool" = "claude" ]; then wizard_model="$_cdef";
      else wizard_model="default"; fi
    fi

    jq -n \
      --argjson ra "$(cat "$FLOWAI_HOME/src/core/defaults/skills-role-assignments.json")" \
      --arg gdef "$_gdef" \
      --arg cdef "$_cdef" \
      --arg wbranch "$wizard_branch" \
      --arg wtool "$wizard_tool" \
      --arg wmodel "$wizard_model" \
      --argjson waap "$wizard_auto_approve" \
      '{
        platform: "generic",
        default_model: $gdef,
        claude_default_model: $cdef,
        default_branch: $wbranch,
        master: { tool: $wtool, model: $wmodel },
        layout: "dashboard",
        auto_approve: $waap,
        pipeline: {
          plan: "team-lead",
          tasks: "backend-engineer",
          impl: "backend-engineer",
          review: "reviewer"
        },
        roles: {
          "team-lead":        { tool: $wtool, model: $wmodel },
          "backend-engineer": { tool: $wtool, model: $wmodel },
          "reviewer":         { tool: $wtool, model: $wmodel }
        },
        skills: { role_assignments: $ra },
        graph: {
          enabled: true,
          scan_paths: ["src", "docs", "specs"],
          ignore_patterns: ["*.generated.*", "*.min.js", "*.min.css"],
          max_age_hours: 24,
          auto_build: false,
          semantic_enabled: false
        },
        mcp: {
          servers: {
            context7: {
              command: "npx",
              args: ["-y", "@upstash/context7-mcp@latest"],
              description: "Real-time library documentation for AI agents",
              default: true
            }
          }
        }
      }' > "$FLOWAI_DIR/config.json"

    log_success "Wrote $FLOWAI_DIR/config.json"
  fi
fi

mkdir -p "$PWD/specs"

if [ "${FLOWAI_TESTING:-0}" != "1" ]; then
  if ! flowai_specify_is_present "$PWD"; then
    log_info "Attempting Spec Kit bootstrap (requires 'uv')..."
    if ! flowai_specify_ensure "$PWD"; then
      log_warn "Spec Kit automated install failed (is 'uv' installed?)."
      printf '%s\n' "  • Install manually: https://github.github.io/spec-kit/installation.html"
    fi
  fi
fi

if [[ ! -f "$FLOWAI_DIR/roles/master.md" ]] && [[ -f "$FLOWAI_HOME/src/roles/master.md" ]]; then
  log_info "Tip: copy bundled roles to customize:"
  for f in "$FLOWAI_HOME/src/roles/"*.md; do
    [[ -f "$f" ]] || continue
    printf "  cp %s %s\n" "$f" "$FLOWAI_DIR/roles/"
  done
fi

if [[ "${FLOWAI_TESTING:-0}" != "1" ]] && [[ -f "$FLOWAI_DIR/config.json" ]]; then
  export FLOWAI_CONFIG="$FLOWAI_DIR/config.json"
  # shellcheck source=src/core/config-validate.sh
  source "$FLOWAI_HOME/src/core/config-validate.sh"
  if ! flowai_config_validate_models; then
    log_warn "Model fields do not match models-catalog.json — run: flowai validate"
  fi
fi

log_success "FlowAI is ready."
log_info "Next: customize $FLOWAI_DIR/config.json and optionally copy roles from $FLOWAI_HOME/src/roles/"
log_info "Then run: flowai validate && flowai start"
