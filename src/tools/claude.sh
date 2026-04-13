#!/usr/bin/env bash
# FlowAI Claude Tool Plugin
# Defines the two required plugin API functions:
#   flowai_tool_claude_print_models  — used by: flowai models list claude
#   flowai_tool_claude_run           — used by: ai.sh dispatcher
# shellcheck shell=bash

# Inject FlowAI rules into .claude/CLAUDE.md for subagent propagation.
# Claude Code's --system-prompt does NOT propagate to Agent subagents —
# CLAUDE.md is the ONLY mechanism auto-discovered by all Claude sessions.
# Args: $1=content (tool-agnostic rules from flowai_ai_project_config_content)
flowai_tool_claude_inject_project_config() {
  local content="$1"
  local marker_start="<!-- FLOWAI:START -->"
  local marker_end="<!-- FLOWAI:END -->"
  local claude_dir="$PWD/.claude"
  local claude_md="$claude_dir/CLAUDE.md"
  local block="${marker_start}
${content}
${marker_end}"

  mkdir -p "$claude_dir"
  if [[ -f "$claude_md" ]]; then
    local cleaned
    cleaned="$(sed "/${marker_start}/,/${marker_end}/d" "$claude_md")"
    printf '%s\n\n%s\n' "$cleaned" "$block" > "$claude_md"
  else
    printf '%s\n' "$block" > "$claude_md"
  fi
}

flowai_tool_claude_print_models() {
  # _flowai_print_tool_block is dynamically provided by the caller (models.sh)
  _flowai_print_tool_block "claude"
}

# Brief constraint reminder appended to the END of Claude's context window.
# Combined with the HARD CONSTRAINTS at the TOP of the system prompt, this
# creates a "sandwich" reinforcement — LLMs weight both the beginning and end
# of the context window more heavily than the middle.
readonly _FLOWAI_CLAUDE_CONSTRAINT_REMINDER="REMINDER — MANDATORY RULES (from PIPELINE COORDINATION):
1. You may ONLY write to the OUTPUT FILE in your PIPELINE DIRECTIVE. Do NOT create *_REVIEW.md, *_PLAN.md, *_SUMMARY.md, *_REPORT.md or any other files.
2. If a knowledge graph is available, read GRAPH_REPORT.md BEFORE using search, find, or grep.
3. spec.md is the single source of truth. Verify alignment before completing work."

# Phase-aware tool restrictions for Claude Code.
# Prompt-only constraints aren't 100% reliable — Claude Code's built-in "helpful
# assistant" behavior can override system prompt instructions (e.g., creating
# DEEP_REVIEW_PLAN.md when told not to). This function adds --disallowed-tools
# flags as a hard guardrail that Claude Code cannot bypass.
#
# Reads: FLOWAI_CURRENT_PHASE (set by flowai_ai_run)
_flowai_claude_phase_tool_restrictions() {
  local phase="${FLOWAI_CURRENT_PHASE:-}"
  case "$phase" in
    review)
      # Review phase: verbal only — no file creation allowed
      echo "--disallowed-tools Write"
      ;;
    plan|tasks)
      # Plan/tasks: can only write their one artifact — but Claude Code
      # --disallowed-tools doesn't support path patterns, so we rely on
      # prompt enforcement for these. The sandwich reinforcement + HARD
      # CONSTRAINTS at top handle this case.
      ;;
    # master: needs Write for spec.md + approval marker — cannot restrict
    # impl: needs Write/Edit for source code — no restrictions
  esac
}

# Execute a prompt against the Claude Code CLI.
# Args: $1=model  $2=auto_approve  $3=run_interactive  $4=sys_prompt
# Reads: FLOWAI_DIR (for optional mcp.json), FLOWAI_CURRENT_PHASE (for tool restrictions)
flowai_tool_claude_run() {
  local model="$1"
  local auto_approve="$2"
  local run_interactive="$3"
  local sys_prompt="$4"

  local cmd=(claude --model "$model")

  # Attach MCP config if available
  if [[ -f "${FLOWAI_DIR}/mcp.json" ]]; then
    cmd+=(--mcp-config "${FLOWAI_DIR}/mcp.json")
  fi

  # Permission handling:
  # - "acceptEdits" auto-approves file reads/writes without the scary
  #   "Bypass Permissions" warning that frightens users.
  # - Non-interactive phases NEED auto-approval because there's no stdin
  #   to grant permissions — without this, Claude silently fails to write files.
  # - Interactive phases use acceptEdits when auto_approve is configured,
  #   otherwise default (user approves each action).
  if [[ "$run_interactive" == "false" ]] || [[ "$auto_approve" == "true" ]]; then
    cmd+=(--permission-mode acceptEdits)
  fi

  # Append constraint reminder to the end of Claude's context (sandwich reinforcement)
  cmd+=(--append-system-prompt "$_FLOWAI_CLAUDE_CONSTRAINT_REMINDER")

  # Phase-aware tool restrictions (hard guardrail)
  local restrictions
  restrictions="$(_flowai_claude_phase_tool_restrictions)"
  if [[ -n "$restrictions" ]]; then
    # shellcheck disable=SC2086
    cmd+=($restrictions)
  fi

  # Initial prompt that anchors the agent to the pipeline workflow.
  # Without this, Claude ignores the system prompt and responds to user input freely.
  local _initial_prompt="Read your PIPELINE DIRECTIVE and HARD CONSTRAINTS in the system prompt. You are inside a FlowAI pipeline phase. Follow the STAGED WORKFLOW exactly as written — begin with step 1 now. Do NOT deviate from the directive."

  if [[ "$run_interactive" == "true" ]]; then
    # Interactive: user can chat with the agent after it starts.
    # Passing a prompt argument without -p keeps the session interactive.
    "${cmd[@]}" --system-prompt "$sys_prompt" "$_initial_prompt" || return $?
    return 0
  fi

  # Non-interactive: agent runs autonomously then MUST exit so the phase run
  # loop can verify the artifact and show the approval gate.
  #
  # Approach: positional prompt + stdin from /dev/null (same as Gemini plugin).
  #   - Positional prompt: streams full output (thinking, tool calls, writes) to
  #     the tmux pane so the user sees progress in real time.
  #   - < /dev/null: closes stdin so Claude exits after completing its task instead
  #     of waiting for user input in the REPL.
  #
  # Why NOT -p: print mode buffers output and hides tool call progress — the tmux
  # pane appears stuck for long-running tasks (e.g., 40+ min impl phase).
  "${cmd[@]}" --system-prompt "$sys_prompt" "$_initial_prompt" < /dev/null || return $?
}

# Non-interactive single-shot invocation.
# Args: $1=model  $2=prompt_file
# Returns: raw LLM output on stdout.
#
# The prompt file contains the full context (role + directive + artifact boundary
# + graph context). It is passed as the user message; a minimal system prompt
# instructs Claude to follow the directive precisely.
flowai_tool_claude_run_oneshot() {
  local model="$1"
  local prompt_file="$2"
  local prompt
  prompt="$(cat "$prompt_file")"

  claude --model "$model" \
    --system-prompt "Follow the directive in the user message precisely. Produce only the requested output." \
    -p "$prompt" < /dev/null 2>/dev/null || echo '{}'
}
