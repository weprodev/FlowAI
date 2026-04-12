#!/usr/bin/env bash
# FlowAI test runner — use case bindings + harness (single entry; bindings are silent on success).
# Usage: ./tests/run.sh
# Verbose bindings: FLOWAI_TEST_VERBOSE=1 ./tests/run.sh
# shellcheck shell=bash

set -euo pipefail

TESTS_ROOT="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(CDPATH="" cd "$TESTS_ROOT/.." && pwd)"
# bin/fai → bin/flowai for harness only (install.sh creates the same symlink under the install prefix).
if [[ "$(uname -s 2>/dev/null)" == MINGW* || "$(uname -s 2>/dev/null)" == MSYS* ]]; then
  cp -f "$REPO_ROOT/bin/flowai" "$REPO_ROOT/bin/fai" 2>/dev/null || true
else
  ( cd "$REPO_ROOT/bin" && ln -sf flowai fai )
fi
export FLOWAI_HOME="$REPO_ROOT"
export FLOWAI_TESTING=1

# Explicit dependency gate: jq is required for almost every suite. Fail fast with
# a clear message instead of silently skipping jq-dependent cases.
if ! command -v jq >/dev/null 2>&1; then
  echo "FlowAI tests require jq (install: brew install jq or apt-get install jq)" >&2
  echo "Set FLOWAI_TEST_ALLOW_MISSING_JQ=1 to force a run (will skip jq-bound cases)." >&2
  if [[ "${FLOWAI_TEST_ALLOW_MISSING_JQ:-0}" != "1" ]]; then
    exit 1
  fi
  export FLOWAI_TEST_SKIP_JQ=1
else
  export FLOWAI_TEST_SKIP_JQ=0
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "FlowAI tests exercise tmux-backed commands. Install tmux (brew install tmux / apt-get install tmux)." >&2
  echo "Set FLOWAI_TEST_ALLOW_MISSING_TMUX=1 to force a run (will skip tmux-bound cases)." >&2
  if [[ "${FLOWAI_TEST_ALLOW_MISSING_TMUX:-0}" != "1" ]]; then
    exit 1
  fi
  export FLOWAI_TEST_SKIP_TMUX=1
else
  export FLOWAI_TEST_SKIP_TMUX=0
fi

# shellcheck source=tests/lib/verify-bindings.sh
source "$TESTS_ROOT/lib/verify-bindings.sh"
if ! flowai_verify_usecase_bindings "$TESTS_ROOT"; then
  exit 1
fi

# shellcheck source=tests/lib/harness.sh
source "$TESTS_ROOT/lib/harness.sh"
# shellcheck source=tests/suites/cli_entrypoint.sh
source "$TESTS_ROOT/suites/cli_entrypoint.sh"
# shellcheck source=tests/suites/lifecycle_happy.sh
source "$TESTS_ROOT/suites/lifecycle_happy.sh"
# shellcheck source=tests/suites/skill_local_path.sh
source "$TESTS_ROOT/suites/skill_local_path.sh"
# shellcheck source=tests/suites/role_override.sh
source "$TESTS_ROOT/suites/role_override.sh"
# shellcheck source=tests/suites/graph_knowledge.sh
source "$TESTS_ROOT/suites/graph_knowledge.sh"
# shellcheck source=tests/suites/event_log.sh
source "$TESTS_ROOT/suites/event_log.sh"
# shellcheck source=tests/suites/tool_plugins.sh
source "$TESTS_ROOT/suites/tool_plugins.sh"
# shellcheck source=tests/suites/phase_signals.sh
source "$TESTS_ROOT/suites/phase_signals.sh"

echo "FlowAI test run — FLOWAI_HOME=$FLOWAI_HOME"

_test_banner() {
  printf '\n\033[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
  printf '\033[1;36m %s\033[0m\n' "$1"
  printf '\033[36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n\n'
}

set +e

_test_banner "CLI Overview & Entrypoints"
flowai_test_s_cli_001
flowai_test_s_cli_002
flowai_test_s_cli_003
flowai_test_s_cli_004
flowai_test_s_cli_005
flowai_test_s_cli_006
flowai_test_s_cli_007
flowai_test_s_cli_008
flowai_test_s_cli_009
flowai_test_s_cli_010
flowai_test_s_cli_011
flowai_test_s_cli_012
flowai_test_s_cli_013
flowai_test_s_cli_014
flowai_test_s_cli_015
flowai_test_s_cli_016
flowai_test_s_cli_017
flowai_test_s_cli_018
flowai_test_s_cli_019
flowai_test_s_cli_020
flowai_test_s_cli_021
flowai_test_s_cli_022
flowai_test_s_cli_023
flowai_test_s_cli_024
flowai_test_s_cli_025
flowai_test_s_cli_026
flowai_test_s_cli_027
flowai_test_s_cli_028
flowai_test_s_cli_029
flowai_test_s_cli_030
flowai_test_s_cli_031
flowai_test_s_cli_032
flowai_test_s_cli_033
flowai_test_s_cli_034
flowai_test_s_cli_035
flowai_test_s_cli_036
flowai_test_s_cli_037
flowai_test_s_cli_038
flowai_test_s_cli_039
flowai_test_s_cli_040
# skill local path
_test_banner "Skills Path Resolution"
flowai_test_s_skl_001
flowai_test_s_skl_002
flowai_test_s_skl_003
flowai_test_s_skl_004
flowai_test_s_skl_005
flowai_test_s_skl_006
flowai_test_s_skl_007
flowai_test_s_skl_008
# role override resolution
_test_banner "Role Overrides & Resolution"
flowai_test_s_role_001
flowai_test_s_role_002
flowai_test_s_role_003
flowai_test_s_role_004
flowai_test_s_role_005
flowai_test_s_role_006
flowai_test_s_role_007
flowai_test_s_role_008
flowai_test_s_role_009
# knowledge graph & wiki
_test_banner "Knowledge Graph & Semantic Extraction"
flowai_test_s_graph_001
flowai_test_s_graph_002
flowai_test_s_graph_003
flowai_test_s_graph_004
flowai_test_s_graph_005
flowai_test_s_graph_006
flowai_test_s_graph_007
flowai_test_s_graph_008
flowai_test_s_graph_009
flowai_test_s_graph_010
flowai_test_s_graph_011
flowai_test_s_graph_012
flowai_test_s_graph_013
flowai_test_s_graph_014
flowai_test_s_graph_015
flowai_test_s_graph_016
flowai_test_s_graph_017
flowai_test_s_graph_018
flowai_test_s_graph_019
flowai_test_s_graph_020
# phase 1+2: chronicle, frontmatter, lint
_test_banner "Graph Chronicle & Structural Lint"
flowai_test_s_graph_021
flowai_test_s_graph_022
flowai_test_s_graph_023
flowai_test_s_graph_024
flowai_test_s_graph_025
flowai_test_s_graph_026
flowai_test_s_graph_027
flowai_test_s_graph_028
flowai_test_s_graph_029
flowai_test_s_graph_030
flowai_test_s_graph_031
flowai_test_s_graph_032
flowai_test_s_graph_033
flowai_test_s_graph_034
flowai_test_s_graph_035
# event log
_test_banner "Pipeline Event Logs & Progress"
flowai_test_s_evt_001
flowai_test_s_evt_002
flowai_test_s_evt_003
flowai_test_s_evt_004
flowai_test_s_evt_005
flowai_test_s_evt_006
# token compression formats
_test_banner "Event Log Token Compression"
flowai_test_s_evt_007
flowai_test_s_evt_008
flowai_test_s_evt_009
flowai_test_s_evt_010
flowai_test_s_evt_011
flowai_test_s_evt_012
# tool plugins
_test_banner "Agent Tool Plugins (Claude/Gemini/Cursor)"
flowai_test_s_tpl_001
flowai_test_s_tpl_002
flowai_test_s_tpl_003
flowai_test_s_tpl_004
flowai_test_s_tpl_005
flowai_test_s_tpl_006
flowai_test_s_tpl_007
# phase signals
_test_banner "Phase Signal Coordination"
flowai_test_s_sig_001
flowai_test_s_sig_002
flowai_test_s_sig_003
flowai_test_s_sig_004
flowai_test_s_sig_005
flowai_test_s_sig_006
flowai_test_s_sig_007
flowai_test_s_sig_008
flowai_test_s_sig_009
set -e

if [[ "${FLOWAI_TEST_FAILURES:-0}" -gt 0 ]]; then
  echo ""
  printf '%s\n' "FAILED: ${FLOWAI_TEST_FAILURES} assertion(s)" >&2
  exit 1
fi

echo ""
echo "All tests passed"
