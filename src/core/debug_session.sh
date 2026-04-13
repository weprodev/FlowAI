#!/usr/bin/env bash
# Optional NDJSON timing logs for DEBUG sessions (set FLOWAI_DEBUG_GEMINI_TIMING=1).
# shellcheck shell=bash

FLOWAI_DEBUG_SESSION_LOG="${FLOWAI_DEBUG_SESSION_LOG:-/Users/michael/Sites/WeProDev/wpd-message-gateway/.cursor/debug-70894f.log}"

# Args: hypothesisId location message json_object_string
flowai_debug_session_log() {
  [[ "${FLOWAI_DEBUG_GEMINI_TIMING:-0}" == "1" ]] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  local logf="$FLOWAI_DEBUG_SESSION_LOG"
  local mirror="${FLOWAI_DIR:-${PWD:-.}/.flowai}/debug_gemini_timing.ndjson"
  [[ -n "$logf" ]] || return 0
  python3 -c '
import json, os, sys, time
path, mirror, hid, loc, msg, data_s = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
try:
    data = json.loads(data_s)
except json.JSONDecodeError:
    data = {"parse_error": True, "raw": data_s[:200]}
rec = {
    "sessionId": "70894f",
    "hypothesisId": hid,
    "location": loc,
    "message": msg,
    "data": data,
    "timestamp": int(time.time() * 1000),
}
line = json.dumps(rec, ensure_ascii=False) + "\n"

def append(p: str) -> None:
    if not p or not p.strip():
        return
    d = os.path.dirname(p)
    if d:
        os.makedirs(d, exist_ok=True)
    with open(p, "a", encoding="utf-8") as f:
        f.write(line)

for target in (path, mirror):
    try:
        append(target)
    except OSError:
        continue
' "$logf" "$mirror" "$1" "$2" "$3" "$4"
}
