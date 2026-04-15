#!/usr/bin/env python3
"""
FlowAI — Cursor Agent stream-json formatter.

Transforms Cursor CLI `--output-format stream-json` into human-readable,
colorized terminal output so pipeline observers can follow the agent's
thinking, tool usage, and reasoning in real time.

Handles both format variants:
  A) type="tool_call:started" / "tool_call:completed"  (newer CLI)
  B) type="tool_call", subtype="started"/"completed"    (older CLI)

Recognized event types:
  thinking / assistant / content — agent reasoning text
  tool_call:started / tool_call:completed  — tool invocations
  error / connection:*  — failures and reconnection events

Non-JSON lines are passed through verbatim so plain-text stderr
from the CLI binary is never swallowed.
"""

import sys
import json
import os

# ── ANSI color helpers ────────────────────────────────────────────────────────
CYAN    = "\033[36m"
GREEN   = "\033[32m"
RED     = "\033[31m"
YELLOW  = "\033[33m"
DIM     = "\033[2m"
BOLD    = "\033[1m"
RESET   = "\033[0m"


# ── Friendly tool names ──────────────────────────────────────────────────────
_TOOL_LABELS = {
    "read_file":        "📖 Reading",
    "readToolCall":     "📖 Reading",
    "edit_file":        "✏️  Editing",
    "editToolCall":     "✏️  Editing",
    "write_file":       "📝 Writing",
    "writeToolCall":    "📝 Writing",
    "run_terminal_cmd": "▶️  Running command",
    "terminalToolCall": "▶️  Running command",
    "list_dir":         "📂 Listing",
    "listDir":          "📂 Listing",
    "search_files":     "🔍 Searching",
    "searchToolCall":   "🔍 Searching",
    "grep_search":      "🔍 Grep",
    "grepToolCall":     "🔍 Grep",
    "codebase_search":  "🔎 Codebase search",
    "delete_file":      "🗑️  Deleting",
}


def _friendly_tool(name: str) -> str:
    """Return a human-friendly label for a tool, or a cleaned-up fallback."""
    if name in _TOOL_LABELS:
        return _TOOL_LABELS[name]
    # Strip common suffixes for readability
    clean = name.replace("ToolCall", "").replace("_", " ").strip()
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


def _extract_tool_info_flat(data: dict):
    """
    Extract tool name & args from FLAT format (newer CLI):
      {"type":"tool_call:started","name":"read_file","arguments":{...}}
    """
    name = data.get("name", "tool")
    args = data.get("arguments", {})
    if isinstance(args, str):
        try:
            args = json.loads(args)
        except json.JSONDecodeError:
            args = {}
    return name, args


def _extract_tool_info_nested(tc: dict):
    """
    Extract tool name & args from NESTED format (older CLI):
      {"tool_call":{"readToolCall":{"args":{"path":"..."},...}}}
    """
    skip_keys = {"name", "id", "call_id"}
    for key, val in tc.items():
        if key in skip_keys:
            continue
        if isinstance(val, dict):
            args = val.get("args", {})
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except json.JSONDecodeError:
                    args = {}
            return key, args
    # Fallback: try top-level name  
    return tc.get("name", "tool"), tc.get("args", {})


def _format_tool_started(name: str, args: dict):
    """Print a human-friendly tool invocation line."""
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


def _format_tool_completed(data: dict, tc: dict):
    """Print a concise tool-completion line."""
    # Check for errors in either format
    result = data.get("result", tc.get("result", {})) if tc else data.get("result", {})
    if isinstance(result, dict):
        # Nested format: result lives inside the tool key  
        for v in tc.values() if tc else []:
            if isinstance(v, dict) and "result" in v:
                result = v["result"]
                break
    
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


def format_stream():
    for line in sys.stdin:
        stripped = line.strip()
        if not stripped:
            continue

        # ── Try to parse as JSON ──────────────────────────────────────────
        try:
            data = json.loads(stripped)
        except json.JSONDecodeError:
            # Plain text (e.g. stderr from CLI startup) — pass through
            print(line, end='', flush=True)
            continue

        if not isinstance(data, dict):
            print(line, end='', flush=True)
            continue

        typ = data.get("type", "")

        # ── Agent thinking / reasoning ────────────────────────────────────
        if typ in ("thinking", "assistant", "content", "text"):
            text = data.get("text", data.get("content", ""))
            if text:
                print(text, end='', flush=True)
            continue

        # ── Tool call: FLAT format (type = "tool_call:started") ───────────
        if typ == "tool_call:started":
            name, args = _extract_tool_info_flat(data)
            _format_tool_started(name, args)
            continue

        if typ == "tool_call:completed":
            _format_tool_completed(data, {})
            continue

        # ── Tool call: NESTED format (type = "tool_call") ─────────────────
        if typ == "tool_call":
            sub = data.get("subtype", "")
            tc = data.get("tool_call", {})

            if sub == "started":
                name, args = _extract_tool_info_nested(tc)
                _format_tool_started(name, args)
            elif sub == "completed":
                _format_tool_completed(data, tc)
            # ignore other subtypes
            continue

        # ── Errors ────────────────────────────────────────────────────────
        if typ == "error":
            msg = data.get("message", data.get("error", "Unknown error"))
            print(f"\n{RED}[Cursor Error] {msg}{RESET}", flush=True)
            continue

        # ── Connection events (reconnecting / reconnected) ────────────────
        if typ.startswith("connection:"):
            status = typ.split(":", 1)[-1]
            print(f"{YELLOW}[Cursor] ↻ {status}{RESET}", flush=True)
            continue

        # ── Fallback: extract any text field ──────────────────────────────
        fallback = data.get("text", data.get("content", data.get("message", "")))
        if fallback:
            print(fallback, end='', flush=True)


if __name__ == "__main__":
    format_stream()
