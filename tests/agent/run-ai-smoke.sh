#!/usr/bin/env bash
# Optional AI layer: deterministic tests first, then Gemini or Claude *reviews* specs vs log.
# Adds value beyond bash: an LLM reads use case intent and comments on alignment / gaps.
#
#   make verify-ai
#   bash tests/agent/run-ai-smoke.sh
#   bash tests/agent/run-ai-smoke.sh --interactive   # prefer TTY / longer session (gemini)
#
#   FLOWAI_SKIP_AI=1     — stop after deterministic tests (CI)
#   FLOWAI_AI_MODEL=…    — gemini -m / claude --model
#
# shellcheck shell=bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_ROOT="$(CDPATH="" cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(CDPATH="" cd "$TESTS_ROOT/.." && pwd)"
cd "$REPO_ROOT"

PROMPT_HEAD="$TESTS_ROOT/agent/prompts/llm-smoke-review.md"
LOG_FILE="$(mktemp)"
INTERACTIVE=false
[[ "${1:-}" == "--interactive" ]] && INTERACTIVE=true

trap 'rm -f "$LOG_FILE"' EXIT

if [[ "${FLOWAI_SKIP_AI:-}" == "1" ]]; then
  echo "FLOWAI_SKIP_AI=1 — running deterministic tests only."
  exec bash "$TESTS_ROOT/run.sh"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Step 1 — Deterministic tests (bindings + harness)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if ! bash "$TESTS_ROOT/run.sh" >"$LOG_FILE" 2>&1; then
  cat "$LOG_FILE" >&2
  echo "Deterministic tests failed — fix before AI review." >&2
  exit 1
fi
cat "$LOG_FILE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Step 2 — AI review (optional — needs gemini or claude in PATH)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

USECASE_INDEX=""
for p in "$REPO_ROOT/tests/usecases/"[0-9][0-9][0-9]-*.md; do
  [[ -f "$p" ]] || continue
  USECASE_INDEX+="- $(basename "$p")${IFS:0:1}"
done

FULL_PROMPT="$(cat <<EOF
$(cat "$PROMPT_HEAD")

## Use case files in this repo
$USECASE_INDEX

## Deterministic test log (authoritative)
$(cat "$LOG_FILE")
EOF
)"

run_gemini_batch() {
  if [[ "$INTERACTIVE" == true ]]; then
    # Let the CLI own the terminal for a real session when possible
    exec gemini ${FLOWAI_AI_MODEL:+-m "$FLOWAI_AI_MODEL"} -p "$FULL_PROMPT"
  fi
  printf '%s' "$FULL_PROMPT" | gemini -y ${FLOWAI_AI_MODEL:+-m "$FLOWAI_AI_MODEL"}
}

run_claude_batch() {
  if [[ "$INTERACTIVE" == true ]]; then
    exec claude ${FLOWAI_AI_MODEL:+--model "$FLOWAI_AI_MODEL"} -p "$FULL_PROMPT"
  fi
  claude ${FLOWAI_AI_MODEL:+--model "$FLOWAI_AI_MODEL"} --dangerously-skip-permissions -p "$FULL_PROMPT" </dev/null
}

if command -v gemini >/dev/null 2>&1; then
  echo "→ Invoking Gemini CLI…"
  run_gemini_batch || echo "(gemini exited non-zero — check API / quota / network)" >&2
  exit 0
fi

if command -v claude >/dev/null 2>&1; then
  echo "→ Invoking Claude Code CLI…"
  run_claude_batch || echo "(claude exited non-zero — check auth)" >&2
  exit 0
fi

echo ""
echo "No \`gemini\` or \`claude\` in PATH — skipping LLM review."
echo "Install one of them, then re-run: make verify-ai"
echo ""
echo "──────── Copy/paste into any AI terminal client ────────"
printf '%s\n' "$FULL_PROMPT"
exit 0
