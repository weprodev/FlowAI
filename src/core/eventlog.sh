#!/usr/bin/env bash
# FlowAI — Shared event log (cross-agent message bus)
#
# Provides an append-only JSONL event log at .flowai/events.jsonl that gives
# all agents and the master orchestrator visibility into pipeline activity.
#
# Event format (one JSON object per line):
#   {"ts":"ISO-8601","phase":"plan","event":"started","detail":""}
#
# Event types:
#   waiting            — phase is blocked, waiting for upstream signal
#   started            — phase AI run has begun
#   artifact_produced  — phase output file written
#   approved           — human approved the artifact
#   rejected           — human rejected the artifact (detail has reason)
#   progress           — implementation progress update (e.g. "3/7 tasks")
#   phase_complete     — phase fully done (approved + signal fired)
#   pipeline_complete  — all phases done
#   error              — phase encountered an error
#
# shellcheck shell=bash

# shellcheck source=src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"
# shellcheck source=src/core/config.sh
source "$FLOWAI_HOME/src/core/config.sh"
# shellcheck source=src/core/phases.sh
source "$FLOWAI_HOME/src/core/phases.sh"

FLOWAI_EVENTS_FILE="${FLOWAI_DIR:-$PWD/.flowai}/events.jsonl"

# ─── Emit ─────────────────────────────────────────────────────────────────────

# Append an event to the log. Atomic via temp-file + mv to avoid partial writes
# when multiple tmux panes emit concurrently.
# Usage: flowai_event_emit <phase> <event> [detail]
flowai_event_emit() {
  local phase="$1"
  local event="$2"
  local detail="${3:-}"

  # Ensure parent directory exists (guards against calls before flowai_event_reset)
  mkdir -p "$(dirname "$FLOWAI_EVENTS_FILE")" 2>/dev/null || true

  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local line
  line="$(jq -cn \
    --arg ts "$ts" \
    --arg phase "$phase" \
    --arg event "$event" \
    --arg detail "$detail" \
    '{"ts":$ts,"phase":$phase,"event":$event,"detail":$detail}')"

  # Atomic append: write to temp, then append with file-level locking
  local tmp
  tmp="$(mktemp "${FLOWAI_EVENTS_FILE}.XXXXXX")"
  printf '%s\n' "$line" > "$tmp"

  # Use flock if available (Linux), otherwise fall back to simple append
  if command -v flock >/dev/null 2>&1; then
    flock "${FLOWAI_EVENTS_FILE}.lock" bash -c "cat '$tmp' >> '$FLOWAI_EVENTS_FILE'"
  else
    cat "$tmp" >> "$FLOWAI_EVENTS_FILE"
  fi
  rm -f "$tmp"
}

# ─── Read ─────────────────────────────────────────────────────────────────────

# Read the last N events (default: 20).
# Usage: flowai_event_tail [n]
flowai_event_tail() {
  local n="${1:-20}"
  [[ -f "$FLOWAI_EVENTS_FILE" ]] || return 0
  tail -n "$n" "$FLOWAI_EVENTS_FILE"
}

# Read recent events for a specific phase.
# Usage: flowai_event_recent_for_phase <phase> [n]
flowai_event_recent_for_phase() {
  local phase="$1"
  local n="${2:-10}"
  [[ -f "$FLOWAI_EVENTS_FILE" ]] || return 0
  grep "\"phase\":\"${phase}\"" "$FLOWAI_EVENTS_FILE" 2>/dev/null | tail -n "$n"
}

# Read the single most recent event of a given type.
# Usage: flowai_event_latest <event_type>
flowai_event_latest() {
  local event_type="$1"
  [[ -f "$FLOWAI_EVENTS_FILE" ]] || return 0
  grep "\"event\":\"${event_type}\"" "$FLOWAI_EVENTS_FILE" 2>/dev/null | tail -1
}

# Format recent events for prompt injection.
# Format is controlled by config: event_log.prompt_format
#   "compact"  — deduplicated, short timestamps (HH:MM), ~8 tokens/event (default)
#   "minimal"  — phase:event only, no timestamps, ~3 tokens/event
#   "full"     — raw JSONL lines, no transformation
# Usage: flowai_event_format_for_prompt [n]
flowai_event_format_for_prompt() {
  local n="${1:-20}"
  [[ -f "$FLOWAI_EVENTS_FILE" ]] || return 0

  local fmt
  fmt="$(flowai_cfg_read '.event_log.prompt_format' 'compact')"

  case "$fmt" in
    minimal)
      # ~3 tokens per event: just phase:event, collapse consecutive progress
      tail -n "$n" "$FLOWAI_EVENTS_FILE" | jq -rs '
        reduce .[] as $e ([];
          if ($e.event == "progress") and (length > 0) and (.[-1].phase == $e.phase) and (.[-1].event == "progress")
          then .[:-1] + [$e]
          else . + [$e]
          end
        ) |
        .[] |
        "\(.phase):\(.event)"
      ' 2>/dev/null || tail -n "$n" "$FLOWAI_EVENTS_FILE"
      ;;
    full)
      # Raw JSONL — no transformation, maximum detail
      tail -n "$n" "$FLOWAI_EVENTS_FILE"
      ;;
    *)
      # compact (default) — deduplicated, short timestamps
      tail -n "$n" "$FLOWAI_EVENTS_FILE" | jq -rs '
        reduce .[] as $e ([];
          if ($e.event == "progress") and (length > 0) and (.[-1].phase == $e.phase) and (.[-1].event == "progress")
          then .[:-1] + [$e]
          else . + [$e]
          end
        ) |
        .[] |
        (.ts | split("T")[1] | split("Z")[0] | .[0:5]) as $time |
        if .detail != "" and .detail != null
        then "\($time) \(.phase):\(.event) \(.detail)"
        else "\($time) \(.phase):\(.event)"
        end
      ' 2>/dev/null || tail -n "$n" "$FLOWAI_EVENTS_FILE"
      ;;
  esac
}

# ─── Pipeline Status ─────────────────────────────────────────────────────────

# Get a compact summary of pipeline status from the event log.
# Returns: JSON with phase statuses.
flowai_event_pipeline_status() {
  [[ -f "$FLOWAI_EVENTS_FILE" ]] || { printf '{}'; return 0; }

  # Build the phase list as a jq-compatible JSON array from the canonical constant
  local phases_json
  phases_json="$(printf '%s\n' "${FLOWAI_PIPELINE_PHASES[@]}" | jq -Rsc 'split("\n") | map(select(. != ""))')"

  # Build a JSON object with the latest event for each pipeline phase.
  jq -sc --argjson phases "$phases_json" '
    reduce .[] as $e ({};
      if ($e.phase | IN($phases[])) then .[$e.phase] = $e.event else . end
    )
  ' "$FLOWAI_EVENTS_FILE" 2>/dev/null || printf '{}'
}

# Reset the event log (used at pipeline start).
flowai_event_reset() {
  mkdir -p "$(dirname "$FLOWAI_EVENTS_FILE")"
  : > "$FLOWAI_EVENTS_FILE"
  flowai_event_emit "master" "pipeline_initialized" "Event log created"
}
