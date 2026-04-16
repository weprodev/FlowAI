#!/usr/bin/env python3
"""
FlowAI — Claude Code stream-json formatter.

Transforms Claude Code `-p --output-format stream-json --verbose` into
human-readable, colorized terminal output so pipeline observers can follow
the agent's tool usage and reasoning in real time.

Claude Code emits NDJSON with these types:
  system    — session init (tools, model, permissions)
  assistant — model output with content blocks (text, tool_use, tool_result)
  result    — final session summary (cost, usage, duration)

Non-JSON lines are passed through verbatim.
"""

import sys
import json

# ── ANSI color helpers ────────────────────────────────────────────────────────
CYAN    = "\033[36m"
GREEN   = "\033[32m"
RED     = "\033[31m"
YELLOW  = "\033[33m"
DIM     = "\033[2m"
BOLD    = "\033[1m"
MAGENTA = "\033[35m"
RESET   = "\033[0m"


# ── Friendly tool names ──────────────────────────────────────────────────────
_TOOL_LABELS = {
    "Read":       "📖 Reading",
    "Edit":       "✏️  Editing",
    "Write":      "📝 Writing",
    "Bash":       "▶️  Running command",
    "Glob":       "📂 Searching files",
    "Grep":       "🔍 Grep",
    "WebSearch":  "🌐 Web search",
    "WebFetch":   "🌐 Fetching",
    "Agent":      "🤖 Spawning agent",
    "Skill":      "⚡ Using skill",
    "NotebookEdit": "📓 Editing notebook",
}


def _friendly_tool(name: str) -> str:
    if name in _TOOL_LABELS:
        return _TOOL_LABELS[name]
    return f"🪄 {name}"


def _extract_path_from_input(tool_input: dict) -> str:
    for key in ("file_path", "path", "command", "pattern", "query"):
        val = tool_input.get(key, "")
        if val:
            if key == "command":
                return val[:80]
            parts = str(val).replace("\\", "/").split("/")
            return "/".join(parts[-2:]) if len(parts) > 2 else str(val)
    return ""


def _handle_system(data: dict):
    model = data.get("model", "unknown")
    print(f"{DIM}Claude Code session: model={model}{RESET}", flush=True)


def _handle_assistant(data: dict):
    msg = data.get("message", {})
    content = msg.get("content", [])
    for block in content:
        btype = block.get("type", "")
        if btype == "text":
            text = block.get("text", "")
            if text.strip():
                print(text, flush=True)
        elif btype == "tool_use":
            name = block.get("name", "tool")
            tool_input = block.get("input", {})
            label = _friendly_tool(name)
            path = _extract_path_from_input(tool_input)
            if path:
                print(f"{CYAN}{label}: {path}{RESET}", flush=True)
            else:
                print(f"{CYAN}{label}{RESET}", flush=True)
        elif btype == "tool_result":
            pass  # tool results are verbose; skip for clean output


def _handle_result(data: dict):
    duration = data.get("duration_ms", 0)
    cost = data.get("total_cost_usd", 0)
    turns = data.get("num_turns", 0)
    secs = duration / 1000 if duration else 0
    mins = int(secs // 60)
    secs_rem = int(secs % 60)
    time_str = f"{mins}m{secs_rem}s" if mins > 0 else f"{secs_rem}s"
    print(f"\n{GREEN}Done in {time_str} · {turns} turn(s) · ${cost:.4f}{RESET}", flush=True)


def main():
    for raw_line in sys.stdin:
        line = raw_line.rstrip("\n\r")
        if not line:
            continue
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            print(line, flush=True)
            continue

        evt_type = data.get("type", "")
        if evt_type == "system":
            _handle_system(data)
        elif evt_type == "assistant":
            _handle_assistant(data)
        elif evt_type == "result":
            _handle_result(data)
        # Skip unknown types silently


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
