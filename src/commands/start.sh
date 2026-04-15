#!/usr/bin/env bash
# FlowAI — start multi-agent tmux session
# shellcheck shell=bash

set -euo pipefail

# Pane-skip list for resume — must exist before any helper runs under `set -u`.
declare -a _resume_skip_phases=()

source "$FLOWAI_HOME/src/core/log.sh"
source "$FLOWAI_HOME/src/core/config.sh"
source "$FLOWAI_HOME/src/core/session.sh"
# shellcheck source=src/core/spec-readiness.sh
source "$FLOWAI_HOME/src/core/spec-readiness.sh"
source "$FLOWAI_HOME/src/core/mcp-json.sh"
source "$FLOWAI_HOME/src/bootstrap/specify.sh"
source "$FLOWAI_HOME/src/core/graph.sh"
source "$FLOWAI_HOME/src/graph/build.sh"
source "$FLOWAI_HOME/src/core/phases.sh"
source "$FLOWAI_HOME/src/core/version-check.sh"
source "$FLOWAI_HOME/src/os/platform.sh"
source "$FLOWAI_HOME/src/core/ai.sh"

# Wrappers: ShellCheck does not resolve log.sh across FLOWAI_HOME; these tie log_* to a local definition.
_flowai_start_log_header() { log_header "$@"; }
_flowai_start_log_info() { log_info "$@"; }

# Resume helpers — functions before any top-level log_header/log_info (SC2218).
_resume_skip_contains() {
  local q="$1" p
  ((${#_resume_skip_phases[@]})) || return 1
  for p in "${_resume_skip_phases[@]}"; do
    [[ "$p" == "$q" ]] && return 0
  done
  return 1
}

_resume_skip_add() {
  local q="$1"
  _resume_skip_contains "$q" && return 0
  _resume_skip_phases+=("$q")
}

# Persist wizard "skip this pane" choices — survives any in-memory array issues.
_resume_record_pane_skip() {
  printf '%s\n' "$1" >> "$FLOWAI_DIR/.session_pane_skip"
}

_start_merge_session_pane_skip_file() {
  [[ -f "$FLOWAI_DIR/.session_pane_skip" ]] || return 0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    _resume_skip_add "$line"
  done < "$FLOWAI_DIR/.session_pane_skip"
}

# If plan/tasks signals exist (resume wizard touched them, or manual touch), skip
# panes — do NOT require plan.md/tasks.md under _start_resolve_feature_dir; that
# path can mismatch specs/<branch> when multiple feature dirs exist.
_start_sync_resume_skips_from_signals() {
  if [[ -f "$FLOWAI_DIR/signals/plan.ready" ]]; then
    _resume_skip_add "plan"
  fi
  if [[ -f "$FLOWAI_DIR/signals/tasks.ready" ]] && [[ -f "$FLOWAI_DIR/signals/tasks.master_approved.ready" ]]; then
    _resume_skip_add "tasks"
  fi
}

_start_resolve_feature_dir() {
  local cur_branch
  cur_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ -n "$cur_branch" && -d "$PWD/specs/$cur_branch" ]]; then
    printf '%s' "$PWD/specs/$cur_branch"
    return 0
  fi
  local latest
  latest="$(find "$PWD/specs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r | head -1)"
  [[ -n "$latest" ]] && printf '%s' "$latest"
}

_start_write_resume_next_steps() {
  local feature_dir="$1"
  local dest="$FLOWAI_DIR/RESUME_NEXT_STEPS.md"
  cat > "$dest" <<EOF
# FlowAI — next steps (resume)

You approved an existing \`review.md\` as complete. **No tmux session** was started.

Suggested follow-up:
- Merge or open a PR when your branch is ready.
- Run your full test suite, \`make audit\`, or CI before release.
- Clear stale pipeline signals only when starting a truly fresh run: \`rm -f .flowai/signals/*.ready\` (know what you remove).

Feature directory: \`${feature_dir}\`
Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
  log_success "Wrote $dest"
}

_start_check_resume() {
  local feature_dir
  feature_dir="$(_start_resolve_feature_dir)"
  [[ -n "$feature_dir" && -d "$feature_dir" ]] || return 0

  local cancel_rest=false

  # Pipeline order is fixed: spec → plan → tasks → review (do not jump to tasks if plan was never asked).
  log_info "Resume wizard order: spec → plan → tasks → review"

  # 1/4 — spec
  log_info "Resume step 1/4 — Specification (spec.md)"
  if [[ -f "${feature_dir}/spec.md" && -s "${feature_dir}/spec.md" ]]; then
    log_info "Found existing artifact: spec.md"
    if gum confirm "  Approve spec and skip specification handoff (reuse spec.md)?"; then
      touch "$FLOWAI_DIR/signals/spec.ready"
      _resume_skip_phases+=("spec")
      _resume_record_pane_skip "spec"
      flowai_event_emit "spec" "resumed" "Artifact approved from previous session"
      log_success "  Skipping spec phase signal (artifact reused)"
    else
      log_info "  Will redo specification — remaining resume prompts skipped."
      rm -f "${feature_dir}/spec.md"
      cancel_rest=true
    fi
  else
    log_info "  No spec.md in ${feature_dir} — Master will produce the specification in this session."
  fi

  if [[ "$cancel_rest" == true ]]; then
    return 0
  fi

  # 2/4 — plan (always after spec step; never skip ahead to tasks)
  log_info "Resume step 2/4 — Plan (plan.md)"
  if [[ -f "${feature_dir}/plan.md" && -s "${feature_dir}/plan.md" ]]; then
    log_info "Found existing artifact: plan.md"
    if gum confirm "  Approve plan and skip plan phase (reuse plan.md)?"; then
      touch "$FLOWAI_DIR/signals/plan.ready"
      _resume_skip_phases+=("plan")
      _resume_record_pane_skip "plan"
      flowai_event_emit "plan" "resumed" "Artifact approved from previous session"
      log_success "  Skipping plan phase (artifact reused)"
    else
      log_info "  Will redo plan — remaining resume prompts skipped. Plan pane will run (Master stays active)."
      rm -f "${feature_dir}/plan.md"
      if [[ -f "${feature_dir}/spec.md" && -s "${feature_dir}/spec.md" ]]; then
        touch "$FLOWAI_DIR/signals/spec.ready"
      fi
      cancel_rest=true
    fi
  else
    log_info "  No plan.md — cannot resume tasks/review without a plan artifact. Remaining resume prompts skipped."
    cancel_rest=true
  fi

  if [[ "$cancel_rest" == true ]]; then
    return 0
  fi

  # 3/4 — tasks (only after plan.md exists; prerequisite enforced above)
  log_info "Resume step 3/4 — Tasks (tasks.md)"
  if [[ -f "${feature_dir}/tasks.md" && -s "${feature_dir}/tasks.md" ]]; then
    log_info "Found existing artifact: tasks.md"
    if gum confirm "  Approve tasks and skip tasks phase (reuse tasks.md + Master task review)?"; then
      touch "$FLOWAI_DIR/signals/tasks.ready"
      touch "$FLOWAI_DIR/signals/tasks.master_approved.ready"
      _resume_skip_phases+=("tasks")
      _resume_record_pane_skip "tasks"
      flowai_event_emit "tasks" "resumed" "Artifact approved from previous session"
      log_success "  Skipping tasks phase (artifact reused)"
    else
      log_info "  Will redo tasks — remaining resume prompts skipped."
      rm -f "${feature_dir}/tasks.md"
      touch "$FLOWAI_DIR/signals/spec.ready" 2>/dev/null || true
      touch "$FLOWAI_DIR/signals/plan.ready" 2>/dev/null || true
      cancel_rest=true
    fi
  else
    log_info "  No tasks.md — cannot resume review/git prompts without a tasks artifact. Remaining resume prompts skipped."
    cancel_rest=true
  fi

  if [[ "$cancel_rest" == true ]]; then
    return 0
  fi

  # 4/4 — review (only after tasks.md exists; prerequisite enforced above)
  log_info "Resume step 4/4 — Review (review.md)"
  if [[ -f "${feature_dir}/review.md" && -s "${feature_dir}/review.md" ]]; then
    log_info "Found existing artifact: review.md"
    if gum confirm "  Approve review.md as final (no new agent session)?"; then
      _start_write_resume_next_steps "$feature_dir"
      _FLOWAI_RESUME_PIPELINE_COMPLETE_EXIT=1
      flowai_event_emit "review" "resumed" "User marked review complete — skipping tmux start"
      return 0
    fi
    log_info "  Continuing with implementation + QA — Plan/Tasks panes omitted; Master + Implement + Review only."
    rm -f "${feature_dir}/review.md"
    touch "$FLOWAI_DIR/signals/spec.ready"
    touch "$FLOWAI_DIR/signals/plan.ready"
    touch "$FLOWAI_DIR/signals/tasks.ready"
    touch "$FLOWAI_DIR/signals/tasks.master_approved.ready"
    rm -f "$FLOWAI_DIR/signals/impl.code_complete.ready" "$FLOWAI_DIR/signals/impl.ready" 2>/dev/null || true
    _FLOWAI_RESUME_MINIMAL_IMPL=1
    _resume_record_pane_skip "plan"
    _resume_record_pane_skip "tasks"
    cancel_rest=true
  else
    log_info "  No review.md yet — Review runs after Implement completes."
  fi

  if [[ "$cancel_rest" == true ]]; then
    return 0
  fi

  # Optional: existing git changes → skip implementation AI run
  local git_changes
  git_changes="$(git --no-pager diff --stat HEAD 2>/dev/null || true)"
  if [[ -n "$git_changes" ]]; then
    log_info "Found existing code changes:"
    printf '%s\n' "$git_changes"
    if gum confirm "  Keep these changes and skip implementation phase?"; then
      touch "$FLOWAI_DIR/signals/impl.code_complete.ready"
      _resume_skip_phases+=("impl")
      _resume_record_pane_skip "impl"
      flowai_event_emit "impl" "resumed" "Code changes approved from previous session"
      log_success "  Skipping impl phase (code reused)"
    fi
  fi
}

flowai_write_phase_launcher() {
  local name="$1"
  local phase="$2"
  cat > "$FLOWAI_DIR/launch/tmux_${name}.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export FLOWAI_HOME="$FLOWAI_HOME"
export FLOWAI_DIR="$FLOWAI_DIR"
cd "$REPO_ROOT"
exec "\$FLOWAI_HOME/bin/flowai" run $phase
EOF
  chmod +x "$FLOWAI_DIR/launch/tmux_${name}.sh"
}

# Setup-check helpers (file scope — declared before downstream log_*; satisfies ShellCheck SC2218).
_dep_ok()   { printf '  %-14s %s\n' "$1" "${GREEN}✓${RESET} ok"; }
_dep_warn() { printf '  %-14s %s\n' "$1" "${YELLOW}⚠${RESET}  $2"; }
_dep_fail() { printf '  %-14s %s\n' "$1" "${RED}✗${RESET}  $2"; }

# Headless: create the tmux layout but do not attach (CI / no TTY). Gum is not required —
# phase scripts use gum for approval; headless start does not attach to those UIs.
HEADLESS=false
SKIP_GRAPH=false
SKIP_SPEC_READINESS=false
[[ "${FLOWAI_START_HEADLESS:-}" == "1" ]] && HEADLESS=true
[[ "${FLOWAI_SKIP_GRAPH:-}" == "1" ]] && SKIP_GRAPH=true
[[ "${FLOWAI_SKIP_SPEC_READINESS:-}" == "1" ]] && SKIP_SPEC_READINESS=true
for _fa in "$@"; do
  case "$_fa" in
    --headless)            HEADLESS=true ;;
    --skip-graph)          SKIP_GRAPH=true ;;
    --skip-spec-readiness) SKIP_SPEC_READINESS=true ;;
  esac
done
[[ "$SKIP_SPEC_READINESS" == true ]] && export FLOWAI_SKIP_SPEC_READINESS=1

if ! command -v tmux >/dev/null 2>&1; then
  log_error "tmux is not installed. Install: $(flowai_os_install_hint tmux)"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  log_error "jq is required for configuration. Install: $(flowai_os_install_hint jq)"
  exit 1
fi

# ── Knowledge Graph prerequisites (structural pass requirements) ──────────────
# The graph engine uses only standard Unix tools. We verify the key ones here
# so failures have clear error messages rather than cryptic jq/bash errors.
if [[ "${FLOWAI_TESTING:-0}" != "1" ]]; then
  if ! command -v shasum >/dev/null 2>&1 && ! command -v sha256sum >/dev/null 2>&1; then
    log_warn "Neither shasum nor sha256sum found — graph incremental cache disabled (all files will be re-processed)."
    log_info "Install: brew install coreutils (macOS) or use sha256sum (Linux built-in)"
  fi

  # Verify jq supports slurp mode (required for graph JSON accumulation)
  if ! printf '1' | jq -sc '.' >/dev/null 2>&1; then
    log_error "jq version too old — graph engine requires jq >=1.5 with -sc support."
    log_info "Upgrade: brew upgrade jq"
    exit 1
  fi
fi

if [[ "$HEADLESS" != true ]] && ! command -v gum >/dev/null 2>&1; then
  log_error "gum is required for phase approval menus. Install: $(flowai_os_install_hint gum)"
  exit 1
fi

FLOWAI_DIR="$PWD/.flowai"
if [[ ! -d "$FLOWAI_DIR" ]] || [[ ! -f "$FLOWAI_DIR/config.json" ]]; then
  log_error "Not a FlowAI project here — run: flowai init"
  exit 1
fi

if [[ -f "$FLOWAI_DIR/config.json" ]] && ! jq -e . "$FLOWAI_DIR/config.json" >/dev/null 2>&1; then
  log_error "Invalid JSON in $FLOWAI_DIR/config.json — fix syntax or remove and run: flowai init"
  exit 1
fi

export FLOWAI_DIR
export FLOWAI_HOME
export FLOWAI_CONFIG="$FLOWAI_DIR/config.json"

# ── Config model validation (strict vs models-catalog.json) ───────────────────
if [[ "${FLOWAI_SKIP_CONFIG_VALIDATE:-0}" != "1" ]] && [[ "${FLOWAI_TESTING:-0}" != "1" ]]; then
  # shellcheck source=src/core/config-validate.sh
  source "$FLOWAI_HOME/src/core/config-validate.sh"
  if ! flowai_config_validate_models; then
    log_error "Model validation failed — fix .flowai/config.json or extend models-catalog.json."
    printf '%s\n' "  Run: flowai validate   ·   flowai models list <tool>"
    printf '%s\n' "  Skip (not recommended): FLOWAI_SKIP_CONFIG_VALIDATE=1 or FLOWAI_ALLOW_UNKNOWN_MODEL=1"
    exit 1
  fi
fi

# ── Self-healing dependency check ────────────────────────────────────────────
if [[ "${FLOWAI_TESTING:-0}" != "1" ]]; then
  log_header "FlowAI Setup Check"

  # Non-blocking update check (cached 24h, 3s timeout)
  flowai_version_check_notify || true

  for dep in tmux jq gum; do
    if command -v "$dep" >/dev/null 2>&1; then
      _dep_ok "$dep"
    else
      _dep_fail "$dep" "not found — install: brew install $dep"
    fi
  done

  # Node.js — needed for skills.sh and MCP via npx
  if command -v node >/dev/null 2>&1; then
    _dep_ok "node"
  else
    if [ -t 0 ] && command -v brew >/dev/null 2>&1; then
      _dep_warn "node" "required for skills and MCP"
      printf '\n'
      if command -v gum >/dev/null 2>&1; then
        if gum confirm "  Install Node.js via Homebrew now?"; then
          if brew install node; then
            _dep_ok "node"
          else
            _dep_fail "node" "install failed — visit https://nodejs.org"
          fi
        fi
      else
        read -r -p "  Install Node.js via Homebrew? [Y/n]: " _ans < /dev/tty || true
        if [[ ! "$_ans" =~ ^[nN] ]]; then
          if brew install node; then
            _dep_ok "node"
          else
            _dep_fail "node" "install failed"
          fi
        fi
      fi
    else
      _dep_warn "node" "not found — install via https://nodejs.org for skills/MCP support"
    fi
  fi

  # Spec Kit — auto-repair silently
  specify_health="$(flowai_specify_health "$PWD")"
  case "$specify_health" in
    ok)
      _dep_ok "Spec Kit"
      ;;
    seeded)
      _dep_warn "Spec Kit" "using bundled seed — run: uvx ... specify init . to upgrade"
      ;;
    *)
      _dep_warn "Spec Kit" "repairing..."
      flowai_specify_repair "$PWD"
      # Re-check to show accurate state (ok or seeded)
      specify_health="$(flowai_specify_health "$PWD")"
      if [[ "$specify_health" == "ok" ]]; then
        _dep_ok "Spec Kit"
      else
        _dep_warn "Spec Kit" "using bundled seed (offline)"
      fi
      ;;
  esac

  # Initialise mcp.json from config if not yet present
  MCP_JSON="$FLOWAI_DIR/mcp.json"
  if [[ ! -f "$MCP_JSON" ]]; then
    flowai_mcp_emit_runtime_json > "$MCP_JSON" 2>/dev/null || true
  fi

  printf '\n'
fi

# ── Knowledge Graph (Mandatory) ────────────────────────────────────────────
if [[ "$SKIP_GRAPH" != "true" ]] && flowai_graph_is_enabled; then
  if ! flowai_graph_exists; then
    log_warn "No knowledge graph found. The graph is required for optimal agent performance."
    printf '\n'

    _do_build_graph=false
    if [[ "${FLOWAI_TESTING:-0}" == "1" ]]; then
      # In test mode: skip graph build to avoid LLM calls
      _do_build_graph=false
    elif [[ "$HEADLESS" == "true" ]]; then
      log_warn "Headless mode: skipping graph build. Run 'flowai graph build' manually."
      _do_build_graph=false
    elif command -v gum >/dev/null 2>&1; then
      if gum confirm "Build knowledge graph now? (recommended)"; then
        _do_build_graph=true
      else
        log_warn "Skipping graph build. Run 'flowai graph build' before starting agents."
        log_warn "Or re-run: flowai start --skip-graph (degraded mode)"
      fi
    else
      read -r -p "Build knowledge graph now? [Y/n]: " _graph_ans </dev/tty || true
      if [[ ! "$_graph_ans" =~ ^[nN] ]]; then
        _do_build_graph=true
      else
        log_warn "Skipping graph build. Agents will work without codebase context."
      fi
    fi

    if [[ "$_do_build_graph" == "true" ]]; then
      flowai_graph_build "false"
    fi
  elif flowai_graph_is_stale; then
    log_warn "Knowledge graph is stale. Agents may use outdated context."
    log_info "Run: flowai graph update"
  else
    # (Removed 'local' keyword, assigned directly below)
    _nodes="$(_flowai_graph_node_count)"
    _edges="$(_flowai_graph_edge_count)"
    _age="$(_flowai_graph_age_label)"
    _dep_ok "Knowledge" && printf '  %-14s %s\n' "" "${_nodes} nodes · ${_edges} edges · built ${_age}"
  fi
fi

# ── Spec workspace (feature branch + non-empty specs/<branch>/spec.md) ────────
# Blocks trunk (main/master/develop) and empty/missing spec.md before tmux.
# Interactive: wizard creates branch + template; headless: fail with clear error unless skipped.
if [[ "${FLOWAI_SKIP_SPEC_READINESS:-0}" != "1" ]] && [[ "${FLOWAI_TESTING:-0}" != "1" ]]; then
  if ! flowai_spec_snapshot_ready "$PWD"; then
    if [[ "$HEADLESS" == "true" ]]; then
      log_error "Spec workspace not ready: use a feature branch with non-empty specs/<branch>/spec.md (not main, master, or develop)."
      log_info "Create a branch and spec locally, then re-run. Or run interactively (without --headless) to use the guided setup."
      log_info "Bypass (CI only): FLOWAI_SKIP_SPEC_READINESS=1 or flowai start --skip-spec-readiness"
      exit 1
    fi
    if ! flowai_spec_ensure_before_session "$PWD"; then
      exit 1
    fi
  fi
fi

SESSION="$(flowai_session_name "$PWD")"
export SESSION

REPO_ROOT="$PWD"
export REPO_ROOT

if tmux has-session -t "$SESSION" 2>/dev/null; then
  log_warn "Session '$SESSION' is already running."
  if [[ "$HEADLESS" == true ]]; then
    log_info "Headless: not attaching to existing session."
    exit 0
  fi
  printf "Switching to it... (Ctrl+B D to detach)\n"
  if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "$SESSION"
  else
    tmux attach-session -t "$SESSION"
  fi
  exit 0
fi

_flowai_start_log_header "Spinning up FlowAI: $SESSION"

mkdir -p "$FLOWAI_DIR/signals"
mkdir -p "$FLOWAI_DIR/launch"
# Clean ALL signal files from previous runs to prevent stale state
rm -f "$FLOWAI_DIR/signals"/*.ready 2>/dev/null || true
rm -f "$FLOWAI_DIR/signals"/*.reject 2>/dev/null || true
rm -f "$FLOWAI_DIR/signals"/*.rejection_context 2>/dev/null || true
rm -f "$FLOWAI_DIR/signals"/*.user_approved 2>/dev/null || true
# Clean stale temp files from interrupted Gemini runs
rm -f "$FLOWAI_DIR"/gemini_sys_* 2>/dev/null || true
rm -f "$FLOWAI_DIR/signals/tasks.dispute_round" 2>/dev/null || true
rm -f "$FLOWAI_DIR/gemini_slow_auth_hint_shown" 2>/dev/null || true
rm -f "$FLOWAI_DIR/.session_pane_skip" 2>/dev/null || true

# ── Inject tool project configs for subagent propagation ────────────────────
# Most AI tools' --system-prompt or equivalent does NOT propagate to subagents.
# The ONLY way to ensure subagents follow graph-first navigation and artifact
# rules is via tool-specific project config files:
#   Claude  → .claude/CLAUDE.md
#   Cursor  → .cursorrules
#   Copilot → .github/copilot-instructions.md
#   Gemini  → GEMINI.md
#
# Each tool plugin implements flowai_tool_<name>_inject_project_config().
# The content is tool-agnostic (shared via flowai_ai_project_config_content);
# only the file format/location is tool-specific. Content is wrapped in
# <!-- FLOWAI:START/END --> markers to preserve user content.
if flowai_graph_is_enabled && flowai_graph_exists; then
  flowai_ai_inject_all_tool_configs
  _flowai_start_log_info "Injected graph navigation rules into tool project configs (subagent propagation)"
fi

# Initialize the shared event log for cross-agent visibility
source "$FLOWAI_HOME/src/core/eventlog.sh"
flowai_event_reset

# ── Session resume: existing artifacts — sequential approve / reject (no cascade) ─
# Yes → touch signals & skip that phase's pane where applicable.
# No  → stop asking further questions; start session tailored to the rejection.
# review.md Yes → exit without tmux (next-steps file only).
# review.md No  → Master + Implement + Review only (upstream phases skipped as panes).
_resume_skip_phases=()
_FLOWAI_RESUME_PIPELINE_COMPLETE_EXIT=0
_FLOWAI_RESUME_MINIMAL_IMPL=0

if [[ "$HEADLESS" != true ]] && [[ "${FLOWAI_TESTING:-0}" != "1" ]]; then
  _start_check_resume
fi

if [[ "${_FLOWAI_RESUME_PIPELINE_COMPLETE_EXIT:-0}" -eq 1 ]]; then
  log_header "Resume: workflow complete"
  log_info "No tmux session started. See: $FLOWAI_DIR/RESUME_NEXT_STEPS.md"
  exit 0
fi

_start_sync_resume_skips_from_signals
_start_merge_session_pane_skip_file
if [[ ${#_resume_skip_phases[@]} -gt 0 ]]; then
  log_info "Tmux pane skip (resumed upstream): ${_resume_skip_phases[*]}"
fi

layout="$(flowai_cfg_layout)"

flowai_write_phase_launcher "master" "master"

tmux new-session -d -s "$SESSION" -n "master" -x 260 -y 60
tmux set-option -t "$SESSION" status-right " #[bold]FlowAI v$(cat "$FLOWAI_HOME/VERSION" 2>/dev/null || echo 'dev')#[default] | %H:%M "
tmux set-option -t "$SESSION" mouse on
tmux set-option -t "$SESSION" history-limit 10000

# ─── Phase 1: Create panes/windows and finalize layout ────────────────────
# ALL pane creation, layout changes, and resizing happens BEFORE any send-keys.
# This prevents cursor movement escape codes (^[[B, ^[OB) from being injected
# into running shells when tmux adjusts pane sizes.

master_res="$(flowai_ai_resolve_tool_and_model_for_phase "master")"
tmux set-window-option -t "${SESSION}:master" pane-border-status top
tmux set-window-option -t "${SESSION}:master" pane-border-format " #[bold]#{pane_title}#[default] "
tmux select-pane -t "${SESSION}:master" -T "👑 Master Agent [${master_res%%:*}: ${master_res#*:}]"

# Pipeline phases to launch in tmux windows (skip spec — master handles it interactively)
if [[ "${_FLOWAI_RESUME_MINIMAL_IMPL:-0}" -eq 1 ]]; then
  log_info "Resume layout: Master + Implement + Review only (upstream artifact phases skipped as panes)."
  pipelines=(impl review)
else
  pipelines=("${FLOWAI_PIPELINE_PHASES[@]:1}")
fi
win_index=1

# Collect phase info for send-keys in phase 2
declare -a _phase_targets=()
declare -a _phase_cmds=()

_phase_targets+=("${SESSION}:master")
_phase_cmds+=("bash '$FLOWAI_DIR/launch/tmux_master.sh'")

for phase in "${pipelines[@]}"; do
  # Skip phases that were approved during resume.
  # Do NOT increment win_index here — it tracks actual tmux panes/windows. Skipped
  # phases must not advance the index, or select-pane targets a non-existent pane
  # (e.g. "can't find pane: 4" when only the master pane exists).
  if _resume_skip_contains "$phase"; then
    log_info "Skipping pane for resumed phase: $phase"
    continue
  fi

  flowai_write_phase_launcher "phase_${win_index}" "$phase"

  phase_res="$(flowai_ai_resolve_tool_and_model_for_phase "$phase")"
  phase_title="🤖 Phase: ${phase} [${phase_res%%:*}: ${phase_res#*:}]"

  if [[ "$layout" == "dashboard" ]]; then
    tmux split-window -t "${SESSION}:0" -v
    tmux select-pane -t "${SESSION}:0.${win_index}" -T "$phase_title"
    _phase_targets+=("${SESSION}:0.${win_index}")
  else
    tmux new-window -t "${SESSION}:${win_index}" -n "$phase"
    tmux set-window-option -t "${SESSION}:${win_index}" pane-border-status top
    tmux set-window-option -t "${SESSION}:${win_index}" pane-border-format " #[bold]#{pane_title}#[default] "
    tmux set-option -t "${SESSION}:${win_index}" remain-on-exit off 2>/dev/null || true
    tmux select-pane -t "${SESSION}:${win_index}" -T "$phase_title"
    _phase_targets+=("${SESSION}:${win_index}")
  fi
  _phase_cmds+=("bash '$FLOWAI_DIR/launch/tmux_phase_${win_index}.sh'")
  win_index=$((win_index + 1))
done

# Finalize layout BEFORE starting any shells
if [[ "$layout" == "dashboard" ]]; then
  tmux select-layout -t "${SESSION}:0" main-vertical
  tmux set-window-option -t "${SESSION}:0" main-pane-width 100
  tmux select-layout -t "${SESSION}:0" main-vertical
  tmux select-pane -t "${SESSION}:0.0"
fi

# ─── Phase 2: Send commands to start shells ───────────────────────────────
# Layout is now stable — no more tmux resizing. Safe to start shells without
# cursor escape code noise.
for i in "${!_phase_targets[@]}"; do
  tmux send-keys -t "${_phase_targets[$i]}" "${_phase_cmds[$i]}" Enter
done

log_success "Session started."

if [[ "$HEADLESS" == true ]]; then
  log_info "Headless: session is running; not attaching (no TTY)."
  exit 0
fi

if [[ -n "${TMUX:-}" ]]; then
  tmux switch-client -t "$SESSION"
else
  tmux attach-session -t "$SESSION"
fi

# Session has finished or user detached.
if [[ -f "${FLOWAI_DIR:-$PWD/.flowai}/signals/pipeline.complete" ]]; then
  # Clear the screen to bring the summary to the top for a clean finish
  clear || true
  log_success "Pipeline complete! All phases approved."
  log_info "Review the final artifacts in specs/ and the implemented code."
  printf '\n'
  log_info "Next steps:"
  log_info "  1. Review changes:  git diff"
  log_info "  2. Commit changes:  git add -A && git commit -m 'feat: ...'"
  log_info "  3. Update graph:    flowai graph update"
  log_info "  4. Push:            git push"
  printf '\n'
  log_success "🎉 Happy FlowAI! Feature complete."
  rm -f "${FLOWAI_DIR:-$PWD/.flowai}/signals/pipeline.complete"
fi
