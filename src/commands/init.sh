#!/usr/bin/env bash
# FlowAI — initialize .flowai in the current repository
# Usage: flowai init [--with-specify]   (Spec Kit bootstrap is optional — can download tools)
# shellcheck shell=bash

set -euo pipefail

source "$FLOWAI_HOME/src/core/log.sh"
# shellcheck source=src/core/jq.sh
source "$FLOWAI_HOME/src/core/jq.sh"
flowai_prefer_jq_path
# shellcheck source=src/core/phases.sh
source "$FLOWAI_HOME/src/core/phases.sh"
# shellcheck source=src/bootstrap/specify.sh
source "$FLOWAI_HOME/src/bootstrap/specify.sh"
# shellcheck source=src/bootstrap/editor-scaffold.sh
source "$FLOWAI_HOME/src/bootstrap/editor-scaffold.sh"

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

    # ── Collect bundled role names ─────────────────────────────────────────
    declare -a _role_names=()
    if [[ -d "$FLOWAI_HOME/src/roles" ]]; then
      while IFS= read -r _rn; do
        [[ -n "$_rn" ]] && _role_names+=("$_rn")
      done < <(find "$FLOWAI_HOME/src/roles" -maxdepth 1 -name "*.md" -exec basename {} .md \; | sort)
    fi
    if [[ ${#_role_names[@]} -eq 0 ]]; then
      _role_names=("team-lead" "backend-engineer" "reviewer")
    fi

    # ── Wizard Variables Default Values ────────────────────────────────────
    wizard_branch="main"
    wizard_tool="${tool_names[0]}"
    wizard_auto_approve="false"

    # ── Phase defaults ────────────────────────────────────────────────────
    # Bash 3.2 compatible: use parallel arrays keyed by FLOWAI_PIPELINE_PHASES index.
    # FLOWAI_PIPELINE_PHASES=(spec plan tasks impl review)  — 5 elements, indices 0–4
    # Default role per phase:
    _def_role_spec="team-lead"
    _def_role_plan="team-lead"
    _def_role_tasks="backend-engineer"
    _def_role_impl="backend-engineer"
    _def_role_review="reviewer"

    # These will hold per-phase tool/model; filled after wizard_tool is resolved
    _cfg_role_spec=""   _cfg_tool_spec=""   _cfg_model_spec=""
    _cfg_role_plan=""   _cfg_tool_plan=""   _cfg_model_plan=""
    _cfg_role_tasks=""  _cfg_tool_tasks=""  _cfg_model_tasks=""
    _cfg_role_impl=""   _cfg_tool_impl=""   _cfg_model_impl=""
    _cfg_role_review="" _cfg_tool_review="" _cfg_model_review=""

    # ── Interactive Setup Wizard ──────────────────────────────────────────
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

      # 4. Phase Agent Configuration
      printf "── Phase Agent Configuration ──────────────────────────────────\n\n"
      _default_model="$(jq -r --arg t "$wizard_tool" '.tools[$t].default_id // "default"' "$_mc" 2>/dev/null || echo 'default')"
      printf "FlowAI runs %d pipeline phases. Each phase is assigned a role with its own AI tool and model.\n" "${#FLOWAI_PIPELINE_PHASES[@]}"
      printf "Default: all phases use %s / %s.\n\n" "$wizard_tool" "$_default_model"

      _configure_phases="no"
      read -r -p "Configure per-phase agents now? [y/N]: " ans_phases
      if [[ "$ans_phases" =~ ^[Yy]$ ]]; then
        _configure_phases="yes"
      fi
      printf "\n"

      if [[ "$_configure_phases" == "yes" ]]; then
        for phase in "${FLOWAI_PIPELINE_PHASES[@]}"; do
          # Read current defaults for this phase
          eval "_cur_role=\"\${_def_role_${phase}}\""
          _cur_tool="$wizard_tool"

          printf "  Phase: %s\n" "$phase"
          
          # Role selection
          if command -v gum >/dev/null 2>&1; then
            _sel_role="$(gum choose --header "    Role for '$phase' (default: $_cur_role):" "${_role_names[@]}" 2>/dev/null)" || _sel_role=""
            [[ -z "$_sel_role" ]] && _sel_role="$_cur_role"
          else
            printf "    Available roles: %s\n" "${_role_names[*]}"
            read -r -p "    Role [$_cur_role]: " _sel_role
            [[ -z "$_sel_role" ]] && _sel_role="$_cur_role"
          fi
          eval "_cfg_role_${phase}=\"\$_sel_role\""

          # Tool selection
          if command -v gum >/dev/null 2>&1; then
            _sel_tool="$(gum choose --header "    Tool for '$phase' (default: $_cur_tool):" "${tool_names[@]}" 2>/dev/null)" || _sel_tool=""
            [[ -z "$_sel_tool" ]] && _sel_tool="$_cur_tool"
          else
            printf "    Available tools: %s\n" "${tool_names[*]}"
            read -r -p "    Tool [$_cur_tool]: " _sel_tool
            [[ -z "$_sel_tool" ]] && _sel_tool="$_cur_tool"
          fi
          eval "_cfg_tool_${phase}=\"\$_sel_tool\""

          # Model selection — show catalog for the chosen tool
          _ptool="$_sel_tool"
          _pmodel_default="$(jq -r --arg t "$_ptool" '.tools[$t].default_id // "default"' "$_mc" 2>/dev/null || echo 'default')"

          if command -v gum >/dev/null 2>&1; then
            declare -a _model_choices=()
            while IFS= read -r mid; do
              [[ -n "$mid" ]] && _model_choices+=("$mid")
            done < <(jq -r --arg t "$_ptool" '.tools[$t].models[].id' "$_mc" 2>/dev/null)
            if [[ ${#_model_choices[@]} -gt 0 ]]; then
              _sel_model="$(gum choose --header "    Model for '$phase' (default: $_pmodel_default):" "${_model_choices[@]}" 2>/dev/null)" || _sel_model=""
              [[ -z "$_sel_model" ]] && _sel_model="$_pmodel_default"
            else
              _sel_model="$_pmodel_default"
            fi
          else
            printf "    Models for %s: " "$_ptool"
            jq -r --arg t "$_ptool" '.tools[$t].models[].id' "$_mc" 2>/dev/null | tr '\n' ', ' || true
            printf "\n"
            read -r -p "    Model [$_pmodel_default]: " _sel_model
            [[ -z "$_sel_model" ]] && _sel_model="$_pmodel_default"
          fi
          eval "_cfg_model_${phase}=\"\$_sel_model\""

          printf "\n"
        done
      fi
    fi

    # ── Determine default model based on primary tool ─────────────────────
    if [[ -f "$_mc" ]]; then
      wizard_model="$(jq -r --arg t "$wizard_tool" '.tools[$t].default_id // "default"' "$_mc")"
    else
      if [ "$wizard_tool" = "gemini" ]; then wizard_model="$_gdef";
      elif [ "$wizard_tool" = "claude" ]; then wizard_model="$_cdef";
      else wizard_model="default"; fi
    fi

    # ── Fill defaults for phases not explicitly configured ─────────────────
    for phase in "${FLOWAI_PIPELINE_PHASES[@]}"; do
      eval "_cr=\"\${_cfg_role_${phase}}\""
      eval "_ct=\"\${_cfg_tool_${phase}}\""
      eval "_cm=\"\${_cfg_model_${phase}}\""
      if [[ -z "$_cr" ]]; then
        eval "_cr=\"\${_def_role_${phase}:-backend-engineer}\""
        eval "_cfg_role_${phase}=\"\$_cr\""
      fi
      if [[ -z "$_ct" ]]; then
        eval "_cfg_tool_${phase}=\"\$wizard_tool\""
      fi
      if [[ -z "$_cm" ]]; then
        eval "_cfg_model_${phase}=\"\$wizard_model\""
      fi
    done

    # ── Build pipeline and roles JSON ─────────────────────────────────────
    pipeline_json="{}"
    roles_json="{}"
    for phase in "${FLOWAI_PIPELINE_PHASES[@]}"; do
      eval "_pr=\"\${_cfg_role_${phase}}\""
      eval "_pt=\"\${_cfg_tool_${phase}}\""
      eval "_pm=\"\${_cfg_model_${phase}}\""
      pipeline_json="$(jq -n --argjson p "$pipeline_json" --arg k "$phase" --arg v "$_pr" '$p + {($k): $v}')"
      roles_json="$(jq -n --argjson r "$roles_json" --arg k "$_pr" --arg t "$_pt" --arg m "$_pm" \
        '$r + {($k): {tool: $t, model: $m}}')"
    done

    jq -n \
      --argjson ra "$(cat "$FLOWAI_HOME/src/core/defaults/skills-role-assignments.json")" \
      --arg gdef "$_gdef" \
      --arg cdef "$_cdef" \
      --arg wbranch "$wizard_branch" \
      --arg wtool "$wizard_tool" \
      --arg wmodel "$wizard_model" \
      --argjson waap "$wizard_auto_approve" \
      --argjson pipeline "$pipeline_json" \
      --argjson roles "$roles_json" \
      '{
        platform: "generic",
        default_model: $gdef,
        claude_default_model: $cdef,
        default_branch: $wbranch,
        master: { tool: $wtool, model: $wmodel },
        layout: "dashboard",
        auto_approve: $waap,
        pipeline: $pipeline,
        roles: $roles,
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

# ── Editor Config Scaffolding ───────────────────────────────────────────────
# Create project-level context files for AI editors (.claude, .gemini, .cursor, .github)
# so that agents immediately understand the project structure and FlowAI conventions.
_scaffold_tool="${wizard_tool:-gemini}"
if [[ -f "$FLOWAI_DIR/config.json" ]]; then
  _scaffold_tool="$(jq -r '.master.tool // "gemini"' "$FLOWAI_DIR/config.json" 2>/dev/null || echo "gemini")"
fi

if [[ -t 0 ]] && [[ "${FLOWAI_TESTING:-0}" != "1" ]]; then
  flowai_scaffold_editor_interactive "$PWD" "$_scaffold_tool"
else
  flowai_scaffold_editor_noninteractive "$PWD" "$_scaffold_tool"
fi

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
