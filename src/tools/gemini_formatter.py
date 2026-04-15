#!/usr/bin/env python3
"""
FlowAI — Gemini CLI stream-json formatter.

Transforms Gemini CLI `--output-format stream-json` into human-readable,
colorized terminal output so pipeline observers can follow the agent's
thinking, tool usage, and reasoning in real time.

Gemini CLI emits NDJSON (newline-delimited JSON) events with these types:
  text     — streamed text content from the model
  thought  — reasoning/thinking trace (Gemini 3.x models)
  tool_call — tool invocation (read_file, edit_file, grep, shell, etc.)
  result   — final session summary (token usage, latency)
  error    — failure events

Non-JSON lines are passed through verbatim so plain-text stderr
from the CLI binary is never swallowed.
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
    "read_file":        "📖 Reading",
    "readFile":         "📖 Reading",
    "edit_file":        "✏️  Editing",
    "editFile":         "✏️  Editing",
    "write_file":       "📝 Writing",
    "writeFile":        "📝 Writing",
    "run_terminal_cmd": "▶️  Running command",
    "shell":            "▶️  Running command",
    "list_dir":         "📂 Listing",
    "listDir":          "📂 Listing",
    "search_files":     "🔍 Searching",
    "grep_search":      "🔍 Grep",
    "grep":             "🔍 Grep",
    "codebase_search":  "🔎 Codebase search",
    "web_search":       "🌐 Web search",
    "web_fetch":        "🌐 Fetching URL",
    "delete_file":      "🗑️  Deleting",
    "glob":             "📂 Glob search",
}


def _friendly_tool(name: str) -> str:
    """Return a human-friendly label for a tool, or a cleaned-up fallback."""
    if name in _TOOL_LABELS:
        return _TOOL_LABELS[name]
    # Strip common suffixes for readability
    clean = name.replace("_", " ").strip()
    return f"🪄 {clean.capitalize()}" if clean else f"🪄 {name}"


def _extract_path(args: dict) -> str:
    """Pull a short, readable file reference from tool arguments."""
    path = args.get("path", args.get("file", args.get("directory", "")))
    if not path:
        return ""
    # Shorten to the last 2 path components for readability
    parts = path.replace("\\", "/").split("/")
    short = "/".join(parts[-2:]) if len(parts) > 2 else path
    return short


def _format_tool_call(data: dict):
    """Print a human-friendly tool invocation line from a Gemini tool_call event."""
    # Gemini stream-json tool_call events carry name + arguments at top level
    name = data.get("name", data.get("function", "tool"))
    args = data.get("arguments", data.get("args", {}))
    status = data.get("status", data.get("subtype", ""))

    if isinstance(args, str):
        try:
            args = json.loads(args)
        except json.JSONDecodeError:
            args = {}

    # Handle started/completed sub-states if present
    if status == "completed":
        result = data.get("result", {})
        has_error = False
        if isinstance(result, dict):
            has_error = "error" in result
        if has_error:
            err_detail = result.get("error", "unknown")
            if isinstance(err_detail, dict):
                err_detail = err_detail.get("message", str(err_detail))
            if len(str(err_detail)) > 120:
                err_detail = str(err_detail)[:117] + "..."
            print(f"{RED}  ✗ Failed: {err_detail}{RESET}", flush=True)
        else:
            print(f"{GREEN}  ✓ Done{RESET}", flush=True)
        return

    # Default: show the tool invocation (started or unqualified)
    label = _friendly_tool(name)
    path = _extract_path(args)

    if path:
        print(f"{CYAN}{label} {BOLD}{path}{RESET}", flush=True)
    else:
        # Show a compact arg summary for non-file tools
        summary_parts = []
        for k, v in args.items():
            if isinstance(v, str) and len(v) > 60:
                v = v[:57] + "..."
            summary_parts.append(f"{k}={v!r}" if isinstance(v, str) else f"{k}={v}")
        summary = ", ".join(summary_parts)
        if len(summary) > 100:
            summary = summary[:97] + "..."
        if summary:
            print(f"{CYAN}{label} {DIM}({summary}){RESET}", flush=True)
        else:
            print(f"{CYAN}{label}{RESET}", flush=True)


def format_stream():
    for line in sys.stdin:
        stripped = line.strip()
        if not stripped:
            continue

        # ── Try to parse as JSON ──────────────────────────────────────────
        try:
            data = json.loads(stripped)
        except json.JSONDecodeError:
            # Plain text (e.g. stderr from CLI startup, [LocalAgentExecutor]) — pass through dimmed
            if stripped.startswith("[LocalAgentExecutor]"):
                print(f"{DIM}{stripped}{RESET}", flush=True)
            else:
                print(line, end='', flush=True)
            continue

        if not isinstance(data, dict):
            print(line, end='', flush=True)
            continue

        typ = data.get("type", "")

        # ── Agent text output (streamed content) ──────────────────────────
        if typ in ("text", "content", "assistant"):
            text = data.get("text", data.get("content", ""))
            if text:
                print(text, end='', flush=True)
            continue

        # ── Thinking / reasoning trace ────────────────────────────────────
        if typ in ("thought", "thinking"):
            text = data.get("text", data.get("content", ""))
            if text:
                print(f"{DIM}{text}{RESET}", end='', flush=True)
            continue

        # ── Tool call events ──────────────────────────────────────────────
        if typ == "tool_call" or typ.startswith("tool_call:"):
            # Handle both flat (type=tool_call:started) and nested (type=tool_call, subtype=started)
            if typ == "tool_call:started":
                name = data.get("name", "tool")
                args = data.get("arguments", {})
                if isinstance(args, str):
                    try:
                        args = json.loads(args)
                    except json.JSONDecodeError:
                        args = {}
                label = _friendly_tool(name)
                path = _extract_path(args)
                if path:
                    print(f"{CYAN}{label} {BOLD}{path}{RESET}", flush=True)
                else:
                    summary_parts = []
                    for k, v in args.items():
                        if isinstance(v, str) and len(v) > 60:
                            v = v[:57] + "..."
                        summary_parts.append(f"{k}={v!r}" if isinstance(v, str) else f"{k}={v}")
                    summary = ", ".join(summary_parts)
                    if len(summary) > 100:
                        summary = summary[:97] + "..."
                    if summary:
                        print(f"{CYAN}{label} {DIM}({summary}){RESET}", flush=True)
                    else:
                        print(f"{CYAN}{label}{RESET}", flush=True)
            elif typ == "tool_call:completed":
                result = data.get("result", {})
                has_error = isinstance(result, dict) and "error" in result
                if has_error:
                    err_detail = result.get("error", "unknown")
                    if isinstance(err_detail, dict):
                        err_detail = err_detail.get("message", str(err_detail))
                    if len(str(err_detail)) > 120:
                        err_detail = str(err_detail)[:117] + "..."
                    print(f"{RED}  ✗ Failed: {err_detail}{RESET}", flush=True)
                else:
                    print(f"{GREEN}  ✓ Done{RESET}", flush=True)
            else:
                # Generic tool_call (Gemini native format without colon subtypes)
                _format_tool_call(data)
            continue

        # ── Errors ────────────────────────────────────────────────────────
        if typ == "error":
            msg = data.get("message", data.get("error", "Unknown error"))
            print(f"\n{RED}[Gemini Error] {msg}{RESET}", flush=True)
            continue

        # ── Result / session summary ──────────────────────────────────────
        if typ == "result":
            # Optional: show token usage if present
            usage = data.get("usage", data.get("stats", {}))
            if isinstance(usage, dict) and usage:
                parts = []
                for k in ("input_tokens", "output_tokens", "total_tokens"):
                    if k in usage:
                        parts.append(f"{k.replace('_', ' ')}: {usage[k]}")
                if parts:
                    print(f"\n{DIM}[Session] {', '.join(parts)}{RESET}", flush=True)
            continue

        # ── Connection events ─────────────────────────────────────────────
        if typ.startswith("connection:"):
            status = typ.split(":", 1)[-1]
            print(f"{YELLOW}[Gemini] ↻ {status}{RESET}", flush=True)
            continue

        # ── Fallback: extract any text field ──────────────────────────────
        fallback = data.get("text", data.get("content", data.get("message", "")))
        if fallback:
            print(fallback, end='', flush=True)


if __name__ == "__main__":
    format_stream()
